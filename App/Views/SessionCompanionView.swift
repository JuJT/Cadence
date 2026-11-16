import SwiftUI
import UniformTypeIdentifiers

struct SessionCompanionView: View {
    @ObservedObject private var companion = SessionCompanionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioPicker = false
    @State private var showFocusSetup = false

    var body: some View {
        List {
            Section("Musique") {
                if let track = companion.currentTrack {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(track.title, systemImage: "music.note").font(.headline).lineLimit(3)
                        Slider(value: Binding(get: { companion.position }, set: { companion.seek(to: $0) }), in: 0...max(1, companion.duration))
                            .accessibilityLabel("Position dans le fichier audio")
                        HStack {
                            Text(audioTime(companion.position))
                            Spacer()
                            Text(audioTime(companion.duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 24) {
                            Button("Précédent", systemImage: "backward.end.fill") { companion.previousTrack() }
                                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                            Button(companion.isPlaying ? "Pause" : "Lire", systemImage: companion.isPlaying ? "pause.fill" : "play.fill") { companion.toggleAudio() }
                                .labelStyle(.iconOnly).font(.title2).frame(minWidth: 52, minHeight: 52)
                                .accessibilityIdentifier("companion.audio.toggle")
                            Button("Suivant", systemImage: "forward.end.fill") { companion.nextTrack() }
                                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }.frame(maxWidth: .infinity).buttonStyle(.borderless)
                        HStack {
                            Image(systemName: "speaker.fill")
                            Slider(value: $companion.volume, in: 0...1)
                                .accessibilityLabel("Volume du lecteur Cadenza")
                            Image(systemName: "speaker.wave.3.fill")
                        }.foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Button("Ajouter depuis Fichiers", systemImage: "folder.badge.plus") { showAudioPicker = true }
                    .accessibilityIdentifier("companion.audio.import")
                Button("Ouvrir Deezer", systemImage: "music.note.list") { companion.openDeezer() }
                Text("Les fichiers ajoutés se lisent ici et restent sur l’iPhone. Pour Deezer ou une lecture déjà lancée ailleurs, utilisez les commandes de l’écran verrouillé ou du Centre de contrôle.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !companion.tracks.isEmpty {
                Section("Mes fichiers audio") {
                    ForEach(companion.tracks) { track in
                        Button { companion.play(track) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: companion.currentTrackID == track.id && companion.isPlaying ? "waveform" : "play.circle")
                                Text(track.title).foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                if companion.currentTrackID == track.id { Image(systemName: "checkmark").accessibilityLabel("Fichier sélectionné") }
                            }.frame(minHeight: 38)
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Concentration pendant la séance") {
                Toggle("Appeler mon raccourci automatiquement", isOn: $companion.focusEnabled)
                    .accessibilityIdentifier("companion.focus.enabled")
                TextField("Nom du raccourci", text: $companion.focusShortcutName)
                    .autocorrectionDisabled().textInputAutocapitalization(.words)
                Button("Configurer une fois dans Raccourcis", systemImage: "wand.and.stars") { showFocusSetup = true }
                if companion.activeSessionID != nil {
                    Button("Activer pour cette séance", systemImage: "moon.fill") { companion.enableFocusForCurrentSession() }
                }
                Button("Terminer le mode de cette séance", systemImage: "moon") { companion.disableManagedFocus() }
                    .disabled(!companion.canEndManagedFocus)
                Text(companion.focusStatusText).font(.footnote).foregroundStyle(.secondary)
                Text("iOS réserve l’activation de Concentration à Raccourcis. Une pause conserve le mode ; la fin de la séance appelle sa désactivation. Le raccourci conserve tout mode déjà actif.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .cadenceListStyle()
        .navigationTitle("Musique et concentration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): companion.importAudio(urls)
            case .failure(let error): companion.audioError = "Sélection audio impossible : \(error.localizedDescription)"
            }
        }
        .alert("Musique", isPresented: Binding(get: { companion.audioError != nil }, set: { if !$0 { companion.audioError = nil } })) {
            Button("Compris", role: .cancel) { companion.audioError = nil }
        } message: { Text(companion.audioError ?? "") }
        .sheet(isPresented: $showFocusSetup) { NavigationStack { FocusShortcutSetupView() } }
    }

    private func audioTime(_ value: Double) -> String {
        let seconds = Int(min(max(value.isFinite ? value : 0, 0), 3_155_760_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FocusShortcutSetupView: View {
    @ObservedObject private var companion = SessionCompanionService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Créer le raccourci") {
                Text("Dans Raccourcis, créez un raccourci nommé exactement « \(companion.focusShortcutName) ». Il reçoit le texte on ou off de Cadenza.")
                Text("Si Entrée du raccourci est on : obtenez la concentration actuelle. Si un mode est déjà actif, renvoyez le texte kept sans le modifier. Sinon, activez Ne pas déranger jusqu’à désactivation et renvoyez le texte enabled.")
                Text("Sinon, désactivez uniquement Ne pas déranger et renvoyez le texte disabled. Utilisez une action Texte en fin de chaque branche pour renvoyer ce résultat.")
                Text("Le retour à Cadenza est géré automatiquement. N’ajoutez pas une action qui ouvre une autre app à la fin du raccourci.")
                Button("Ouvrir Raccourcis", systemImage: "arrow.up.forward.app") {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                }
            }
            Section("Puis dans Cadenza") {
                Text("Activez l’appel automatique après avoir configuré le raccourci. Lancez une séance pour vérifier son exécution ; la fin de séance appelle off. L’app ne peut pas créer ce raccourci personnel ni accorder ses autorisations à votre place.")
                Text("Si le mode Concentration était déjà actif, il est conservé à la fin. Si Raccourcis est annulé ou rencontre une erreur, le chronomètre continue normalement et le diagnostic le signale.")
            }
        }
        .cadenceListStyle()
        .navigationTitle("Configurer Concentration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
    }
}
