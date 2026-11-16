import AVFAudio
import Combine
import Foundation
import MediaPlayer
import UIKit

struct LocalStudyAudio: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let title: String
}

@MainActor
final class SessionCompanionService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SessionCompanionService()

    @Published var focusEnabled = UserDefaults.standard.bool(forKey: "cadence.companion.focusEnabled") {
        didSet {
            UserDefaults.standard.set(focusEnabled, forKey: "cadence.companion.focusEnabled")
            if !focusEnabled, managedFocusSessionID != nil { enqueueFocus(enabled: false, sessionID: nil) }
        }
    }
    @Published var focusShortcutName = UserDefaults.standard.string(forKey: "cadence.companion.focusShortcut") ?? "Cadenza Concentration" {
        didSet { UserDefaults.standard.set(focusShortcutName, forKey: "cadence.companion.focusShortcut") }
    }
    @Published private(set) var focusStatusText = "Une configuration initiale dans Raccourcis est nécessaire."
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var tracks: [LocalStudyAudio] = []
    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var volume: Float = 0.7 { didSet { player?.volume = min(1, max(0, volume)) } }
    @Published var audioError: String?

    private struct FocusRequest {
        let token: UUID
        let enabled: Bool
        let sessionID: UUID?
    }
    private var pendingFocusRequest: FocusRequest?
    private var launchedFocusRequest: FocusRequest?
    private var managedFocusSessionID = UserDefaults.standard.string(forKey: "cadence.companion.managedFocusSession").flatMap(UUID.init(uuidString:))
    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private let directory: URL

    var currentTrack: LocalStudyAudio? { tracks.first { $0.id == currentTrackID } }
    var canEndManagedFocus: Bool { managedFocusSessionID != nil }

    private override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        directory = support.appendingPathComponent("Cadence/Audio", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("library-v1.json")),
           let stored = try? JSONDecoder().decode([LocalStudyAudio].self, from: data) {
            tracks = stored.filter { track in
                track.fileName == (track.fileName as NSString).lastPathComponent &&
                !track.fileName.contains("\\") &&
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(track.fileName).path)
            }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationBecameActive() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let kind = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            if kind == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pauseAudio() }
            }
        })
    }

    // Establish the restored baseline without opening another app at launch.
    func synchronizeExistingSession(activeSessionID: UUID?) {
        self.activeSessionID = activeSessionID
        if activeSessionID == nil, managedFocusSessionID != nil {
            focusStatusText = "La précédente séance est terminée. Vous pouvez désactiver son mode Concentration."
        }
    }

    // Call only after a successful persisted change of active-session identity.
    // A pause retains the same identity and deliberately leaves Focus unchanged.
    func sessionDidChange(activeSessionID newID: UUID?) {
        guard activeSessionID != newID else { return }
        activeSessionID = newID
        if let newID, focusEnabled {
            enqueueFocus(enabled: true, sessionID: newID)
        } else if newID == nil {
            pendingFocusRequest = nil
            if managedFocusSessionID != nil { enqueueFocus(enabled: false, sessionID: nil) }
        }
    }

    func enableFocusForCurrentSession() {
        guard let activeSessionID else { return }
        enqueueFocus(enabled: true, sessionID: activeSessionID)
    }

    func disableManagedFocus() {
        guard managedFocusSessionID != nil else {
            focusStatusText = "Aucun mode activé par Cadenza n’est enregistré. Un mode choisi ailleurs reste sous votre contrôle."
            return
        }
        enqueueFocus(enabled: false, sessionID: nil)
    }

    private func applicationBecameActive() {
        if let token = launchedFocusRequest?.token {
            // The callback normally arrives as the app becomes active. If the
            // user returned manually instead, do not keep later requests stuck.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.launchedFocusRequest?.token == token else { return }
                self.launchedFocusRequest = nil
                self.focusStatusText = "Le résultat du raccourci n’a pas été reçu. Vérifiez Concentration dans le Centre de contrôle."
                self.launchPendingFocusRequest()
            }
        } else { launchPendingFocusRequest() }
    }

    private func enqueueFocus(enabled: Bool, sessionID: UUID?) {
        guard !focusShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focusStatusText = "Indiquez le nom de votre raccourci Concentration."
            return
        }
        pendingFocusRequest = FocusRequest(token: UUID(), enabled: enabled, sessionID: sessionID)
        launchPendingFocusRequest()
    }

    private func launchPendingFocusRequest() {
        guard UIApplication.shared.applicationState == .active,
              launchedFocusRequest == nil, let request = pendingFocusRequest else { return }
        pendingFocusRequest = nil
        var components = URLComponents()
        components.scheme = "shortcuts"; components.host = "x-callback-url"; components.path = "/run-shortcut"
        func callback(_ status: String) -> String {
            var value = URLComponents()
            value.scheme = "cadence"; value.host = "companion-focus"
            value.queryItems = [URLQueryItem(name: "token", value: request.token.uuidString), URLQueryItem(name: "status", value: status)]
            return value.url?.absoluteString ?? "cadence://revision"
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: focusShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: request.enabled ? "on" : "off"),
            URLQueryItem(name: "x-success", value: callback("success")),
            URLQueryItem(name: "x-cancel", value: callback("cancel")),
            URLQueryItem(name: "x-error", value: callback("error"))
        ]
        guard let url = components.url else { return }
        launchedFocusRequest = request
        focusStatusText = "Demande transmise à Raccourcis. iOS garde le contrôle du mode Concentration."
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                guard let self, !opened, self.launchedFocusRequest?.token == request.token else { return }
                self.launchedFocusRequest = nil
                self.focusStatusText = "Raccourcis n’a pas pu être ouvert. Vérifiez son installation et le nom du raccourci."
            }
        }
    }

    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "cadence", url.host == "companion-focus" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let request = launchedFocusRequest, value("token") == request.token.uuidString else { return true }
        launchedFocusRequest = nil
        if value("status") == "success" {
            if request.enabled {
                switch value("result")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "enabled":
                    managedFocusSessionID = request.sessionID
                    focusStatusText = "Le raccourci indique avoir activé Ne pas déranger pour cette séance."
                    if activeSessionID != request.sessionID { enqueueFocus(enabled: false, sessionID: nil) }
                case "kept":
                    managedFocusSessionID = nil
                    focusStatusText = "Un mode Concentration était déjà actif ; le raccourci l’a conservé."
                default:
                    focusStatusText = "Raccourci terminé, sans résultat enabled/kept. Vérifiez sa configuration avant d’activer l’automatisme."
                }
            } else {
                managedFocusSessionID = nil
                focusStatusText = "Le raccourci de fin s’est terminé."
            }
        } else {
            focusStatusText = value("status") == "cancel" ? "Demande Concentration annulée dans Raccourcis." : "Le raccourci n’a pas abouti. Vérifiez sa configuration dans Raccourcis."
        }
        UserDefaults.standard.set(managedFocusSessionID?.uuidString, forKey: "cadence.companion.managedFocusSession")
        launchPendingFocusRequest()
        return true
    }

    // Files selected explicitly by the user are copied into the app's private
    // library. No bookmarks or access to unrelated documents are retained.
    func importAudio(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let id = UUID()
                let ext = url.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                let name = id.uuidString + "." + (ext.isEmpty || ext.count > 12 ? "audio" : ext)
                let destination = directory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: destination)
                do {
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                    _ = try AVAudioPlayer(contentsOf: destination)
                }
                catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
                tracks.append(LocalStudyAudio(id: id, fileName: name, title: url.deletingPathExtension().lastPathComponent))
            } catch { audioError = "Import audio impossible : \(error.localizedDescription)" }
        }
        saveLibrary()
    }

    func play(_ track: LocalStudyAudio) {
        do {
            if currentTrackID != track.id || player == nil {
                let value = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(track.fileName))
                value.delegate = self; value.volume = volume
                value.prepareToPlay()
                player = value; currentTrackID = track.id
                duration = value.duration; position = 0
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
            isPlaying = true
            installRemoteCommandsIfNeeded()
            beginProgressUpdates()
            publishNowPlaying()
        } catch {
            player?.pause(); isPlaying = false
            progressTimer?.invalidate(); progressTimer = nil
            audioError = "Lecture impossible : \(error.localizedDescription)"
        }
    }

    func toggleAudio() {
        if isPlaying { pauseAudio() }
        else if let currentTrack { play(currentTrack) }
        else if let first = tracks.first { play(first) }
    }

    func pauseAudio() {
        player?.pause(); isPlaying = false
        position = player?.currentTime ?? position
        progressTimer?.invalidate(); progressTimer = nil
        if currentTrackID != nil { publishNowPlaying() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        position = min(max(0, seconds), duration)
        player?.currentTime = position
        if currentTrackID != nil { publishNowPlaying() }
    }

    func nextTrack() {
        guard !tracks.isEmpty else { return }
        let index = currentTrackID.flatMap { id in tracks.firstIndex { $0.id == id } } ?? -1
        play(tracks[(index + 1) % tracks.count])
    }

    func previousTrack() {
        if position > 3 { seek(to: 0); return }
        guard !tracks.isEmpty else { return }
        let index = currentTrackID.flatMap { id in tracks.firstIndex { $0.id == id } } ?? 0
        play(tracks[(index - 1 + tracks.count) % tracks.count])
    }

    func openDeezer() {
        if isPlaying { pauseAudio() }
        guard let url = URL(string: "https://www.deezer.com/") else { return }
        UIApplication.shared.open(url)
    }

    private func saveLibrary() {
        do { try JSONEncoder().encode(tracks).write(to: directory.appendingPathComponent("library-v1.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { audioError = "Bibliothèque audio non enregistrée : \(error.localizedDescription)" }
    }

    private func beginProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.position = self.player?.currentTime ?? 0
                self.duration = self.player?.duration ?? 0
            }
        }
    }

    private func publishNowPlaying() {
        guard let currentTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func installRemoteCommandsIfNeeded() {
        guard remoteTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        remoteTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let self, let track = self.currentTrack { self.play(track) } }; return .success
        }))
        remoteTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseAudio() }; return .success
        }))
        remoteTargets.append((commands.togglePlayPauseCommand, commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggleAudio() }; return .success
        }))
        remoteTargets.append((commands.nextTrackCommand, commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }; return .success
        }))
        remoteTargets.append((commands.previousTrackCommand, commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousTrack() }; return .success
        }))
        remoteTargets.append((commands.changePlaybackPositionCommand, commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in self?.seek(to: seconds) }; return .success
        }))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false; self.position = self.duration
            if !flag { self.audioError = "Le fichier audio n’a pas pu être lu jusqu’au bout." }
            self.progressTimer?.invalidate(); self.progressTimer = nil
            self.publishNowPlaying()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
