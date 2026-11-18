import AVKit
import MediaPlayer
import SwiftUI

struct SessionCompanionView: View {
    @ObservedObject private var companion = SessionCompanionService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Son de l’iPhone") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Volume", systemImage: "speaker.wave.2.fill").font(.headline)
                    HStack(spacing: 14) {
                        SystemAudioVolumeView()
                            .frame(height: 44)
                            .accessibilityIdentifier("companion.system.volume")
                        SystemAudioRoutePickerView()
                            .frame(width: 44, height: 44)
                            .accessibilityIdentifier("companion.system.routes")
                    }
                    Text("Réglez le volume du son déjà lancé et choisissez sa sortie audio avec AirPlay.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Section("Lecture en cours dans une autre app") {
                Label("Deezer et Fichiers gardent leur lecteur", systemImage: "waveform")
                Text("Pour mettre en pause, changer de piste ou avancer dans le morceau, ouvrez le Centre de contrôle en glissant depuis l’angle supérieur droit de l’écran. Un appui prolongé sur le lecteur affiche ses commandes.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Cadenza laisse votre musique continuer et ne remplace pas le lecteur de l’autre app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Ne pas déranger pendant la séance") {
                if let url = companion.preparedShortcutURL {
                    ShareLink(item: url, preview: SharePreview(SessionCompanionService.preparedShortcutName, image: Image(systemName: "moon.fill"))) {
                        Label("Ajouter le raccourci Concentration", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("companion.focus.add")
                    Text("Ouvrez le fichier avec Raccourcis, puis confirmez Ajouter. Gardez son nom « HongMix Focus ». Les actions sont déjà préparées.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Raccourci libre sous licence MIT, fourni par HongMix et vérifié avant intégration.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Label("Fichier du raccourci indisponible dans cette compilation", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Tester le raccourci ajouté", systemImage: "checkmark.shield") { companion.verifyPreparedFocusShortcut() }
                    .accessibilityIdentifier("companion.focus.test")
                Text("Le test ne change aucun mode Concentration.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Activer pour mes séances chronométrées", isOn: $companion.focusEnabled)
                    .disabled(!companion.preparedShortcutVerified && !companion.focusEnabled)
                    .accessibilityIdentifier("companion.focus.enabled")
                if companion.activeSessionID != nil {
                    Button("Activer pour cette séance", systemImage: "moon.fill") { companion.enableFocusForCurrentSession() }
                        .disabled(!companion.preparedShortcutVerified)
                }
                Button("Terminer le mode de cette séance", systemImage: "moon") { companion.disableManagedFocus() }
                    .disabled(!companion.canEndManagedFocus)
                Text(companion.focusStatusText).font(.footnote).foregroundStyle(.secondary)
                Text("Après l’ajout initial, Cadenza appelle le raccourci au début et à la fin des séances. Une pause conserve le mode. Un mode déjà actif est conservé.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .cadenceListStyle()
        .navigationTitle("Son et concentration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .accessibilityIdentifier("companion.sheet")
    }
}

/// Visible public system control, operated by the user. No hidden slider, KVC,
/// programmatic volume changes or competing audio session are used.
private struct SystemAudioVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.showsRouteButton = false // Modern route UI is AVRoutePickerView below.
        view.tintColor = .systemBlue
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct SystemAudioRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = false
        view.tintColor = .systemBlue
        view.activeTintColor = .systemBlue
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
