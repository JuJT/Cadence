import AVKit
import MediaPlayer
import SwiftUI

struct SessionCompanionView: View {
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
            Section("Lecteur média d’iOS") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Votre lecture, au même endroit", systemImage: "play.rectangle.on.rectangle")
                        .font(.headline)
                    Text("Le Centre de contrôle rassemble le média en cours, quelle que soit son app d’origine.")
                        .font(.subheadline)
                    Label("Glissez vers le bas depuis l’angle supérieur droit de l’écran.", systemImage: "hand.draw")
                    Text("Sur un iPhone avec bouton principal, glissez vers le haut depuis le bord inférieur.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Label("Maintenez le lecteur pour retrouver lecture, pause et pistes.", systemImage: "playpause")
                    Text("Ce lecteur système ne peut pas être intégré à l’intérieur de Cadenza avec les fonctions publiques d’iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityIdentifier("companion.control-center.guide")
            }
            Section("Concentration") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Une séance sans interruption", systemImage: "moon.fill").font(.headline)
                    Text("Dans le Centre de contrôle, touchez Concentration, puis Ne pas déranger. Pour l’activer à chaque ouverture de Cadenza, ajoutez l’app à la programmation d’un mode dans Réglages → Concentration.")
                        .font(.subheadline)
                        .accessibilityIdentifier("companion.focus.guide")
                    Text("Vos séances démarrent et se terminent directement ici. L’ancien appel à Raccourcis a été retiré ; un mode déjà actif reste sous votre contrôle.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
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
