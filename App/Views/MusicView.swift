import CadenceCore
import MediaPlayer
import SwiftUI

struct MusicView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("music.provider") private var provider = "apple"

    var body: some View {
        List {
            Picker("Service de musique", selection: $provider) {
                Text("Apple Music").tag("apple")
                Text("Spotify").tag("spotify")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if provider == "spotify" {
                SpotifyControls()
                SpotifyLinkPlayer()
            } else { AppleMusicControls() }
        }
        .cadenceListStyle()
        .navigationTitle("Musique")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
    }
}

private struct AppleMusicControls: View {
    @Environment(\.scenePhase) private var scene
    @State private var authorization = MPMediaLibrary.authorizationStatus()
    @State private var monitoring = false
    @State private var selection = false
    @State private var title: String?
    @State private var artist: String?
    @State private var playing = false
    @State private var hasQueue = false

    private var player: MPMusicPlayerController { .systemMusicPlayer }

    var body: some View {
        Section("Apple Music") {
            if authorization == .authorized {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title ?? (playing ? "Lecture en cours" : "Aucun morceau sélectionné")).font(.headline)
                    if let artist, !artist.isEmpty { Text(artist).foregroundStyle(.secondary) }
                }
                MusicTransport(playing: playing, previous: { player.skipToPreviousItem() },
                               toggle: { playing ? player.pause() : player.play() },
                               next: { player.skipToNextItem() })
                    .disabled(!hasQueue && !playing)
                Button("Choisir dans ma bibliothèque", systemImage: "music.note.list") { selection = true }
            } else if authorization == .notDetermined {
                Button("Autoriser Apple Music", systemImage: "music.note") {
                    MPMediaLibrary.requestAuthorization { _ in Task { @MainActor in updateAccess() } }
                }.accessibilityIdentifier("music.apple.authorize")
            } else {
                Text("L’accès à votre bibliothèque est désactivé sur cet iPhone.").foregroundStyle(.secondary)
                if let settings = URL(string: UIApplication.openSettingsURLString) { Link("Ouvrir les réglages", destination: settings) }
            }
            Link("Ouvrir Apple Music", destination: URL(string: "https://music.apple.com/")!)
        }
        .onAppear { updateAccess() }
        .onChange(of: scene) { _, phase in
            if phase == .active { updateAccess() } else { stopMonitoring() }
        }
        .onDisappear { stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in readPlayer() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in readPlayer() }
        .sheet(isPresented: $selection) {
            LibraryPicker { items in
                selection = false
                guard let items, items.count > 0 else { return }
                player.setQueue(with: items)
                player.play()
                readPlayer()
            }.ignoresSafeArea()
        }
    }

    private func updateAccess() {
        authorization = MPMediaLibrary.authorizationStatus()
        guard authorization == .authorized else { stopMonitoring(); return }
        if !monitoring {
            player.beginGeneratingPlaybackNotifications()
            monitoring = true
        }
        readPlayer()
    }

    private func readPlayer() {
        guard monitoring else { return }
        let item = player.nowPlayingItem
        title = item?.title
        artist = item?.artist
        playing = player.playbackState == .playing
        hasQueue = item != nil || player.playbackState == .paused
    }

    private func stopMonitoring() {
        if monitoring { player.endGeneratingPlaybackNotifications(); monitoring = false }
    }
}

private struct LibraryPicker: UIViewControllerRepresentable {
    let finished: (MPMediaItemCollection?) -> Void
    func makeCoordinator() -> Delegate { Delegate(finished) }
    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let controller = MPMediaPickerController(mediaTypes: .music)
        controller.allowsPickingMultipleItems = true
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}
    final class Delegate: NSObject, MPMediaPickerControllerDelegate {
        let finished: (MPMediaItemCollection?) -> Void
        init(_ finished: @escaping (MPMediaItemCollection?) -> Void) { self.finished = finished }
        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) { finished(mediaItemCollection) }
        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) { finished(nil) }
    }
}

private struct MusicTransport: View {
    let playing: Bool
    let previous: () -> Void
    let toggle: () -> Void
    let next: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            button("Piste précédente", "backward.end.fill", previous)
            button(playing ? "Pause" : "Lecture", playing ? "pause.fill" : "play.fill", toggle)
            button("Piste suivante", "forward.end.fill", next)
            Spacer()
        }.buttonStyle(.borderless)
    }
    private func button(_ label: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title2).frame(width: 48, height: 48) }.accessibilityLabel(label)
    }
}

private struct SpotifyControls: View {
    @Environment(\.scenePhase) private var scene
    @ObservedObject private var spotify = SpotifyPlayer.shared

    var body: some View {
        Section("Spotify Connect") {
            if spotify.connected {
                if let playback = spotify.playback {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.item?.name ?? "Lecture Spotify").font(.headline)
                        if let artist = playback.item?.credit, !artist.isEmpty { Text(artist) }
                        if let device = playback.device?.name { Label(device, systemImage: "hifispeaker").font(.footnote).foregroundStyle(.secondary) }
                    }
                    MusicTransport(playing: playback.isPlaying, previous: { send(.previous) },
                                   toggle: { send(playback.isPlaying ? .pause : .play) }, next: { send(.next) })
                        .disabled(spotify.busy || playback.device?.isRestricted == true)
                    if let link = playback.item?.spotifyURL { Link("Écouter sur Spotify", destination: link) }
                } else { Text("Lancez une lecture dans Spotify pour retrouver ses commandes ici.").foregroundStyle(.secondary) }
                Button("Actualiser le lecteur", systemImage: "arrow.clockwise") { Task { await spotify.refresh() } }.disabled(spotify.busy)
                Button("Déconnecter Spotify", role: .destructive) { spotify.disconnect() }.disabled(spotify.busy)
            } else {
                Text("Pilotez le lecteur actif de votre compte Spotify Premium.").foregroundStyle(.secondary)
                DisclosureGroup("Configurer Spotify Connect") {
                    Text("Dans le tableau de bord Spotify, créez une application Web API et ajoutez cette adresse de retour.")
                        .font(.footnote)
                    Text(SpotifyConnection.registeredRedirect).font(.footnote.monospaced()).textSelection(.enabled)
                    Link("Tableau de bord Spotify", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    TextField("Client ID public", text: $spotify.clientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(spotify.busy)
                        .accessibilityIdentifier("music.spotify.client")
                    Button("Connecter mon compte", systemImage: "person.crop.circle") { Task { await spotify.connect() } }
                        .disabled(spotify.busy || !SpotifyConnection.validClientID(spotify.clientID.trimmingCharacters(in: .whitespacesAndNewlines)))
                        .accessibilityIdentifier("music.spotify.connect")
                }
            }
            if spotify.busy { ProgressView().accessibilityLabel("Chargement du lecteur Spotify") }
            if let message = spotify.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Link("Ouvrir Spotify", destination: URL(string: "https://open.spotify.com/")!)
        }
        .task(id: scene) {
            guard scene == .active else { return }
            spotify.restore()
            while !Task.isCancelled {
                await spotify.refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onDisappear { spotify.cancelAuthorization() }
    }

    private func send(_ command: SpotifyPlayer.Command) { Task { await spotify.send(command) } }
}
