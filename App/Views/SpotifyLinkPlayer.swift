import CadenceCore
import SwiftUI
import WebKit

struct SpotifyLinkPlayer: View {
    @AppStorage("music.spotify.savedLink") private var saved = ""
    @State private var entry = ""
    @State private var editing = false
    @State private var invalid = false
    private var content: SpotifyContentLink? { SpotifyContentLink(saved) }

    var body: some View {
        Section("Lire un lien Spotify") {
            if let content, !editing {
                SpotifyEmbed(content: content)
                    .id(content.url)
                    .frame(height: content.compact ? 152 : 352)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                Link("Écouter sur Spotify", destination: content.url)
                Button("Changer de lien") { entry = saved; editing = true }
            } else {
                TextField("Lien d’un morceau, d’un album ou d’une playlist", text: $entry)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { load() }
                Button("Afficher le lecteur", systemImage: "play.rectangle") { load() }
                    .disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if invalid { Text("Utilisez un lien open.spotify.com ou une URI spotify.").font(.footnote).foregroundStyle(.secondary) }
                if editing { Button("Annuler") { editing = false; invalid = false } }
            }
            Text("Le lecteur intégré fonctionne avec un lien partagé. Selon le titre et votre accès Spotify, il peut proposer un extrait.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let result = SpotifyContentLink(entry) else { invalid = true; return }
        saved = result.url.absoluteString
        editing = false
        invalid = false
    }
}

private struct SpotifyEmbed: UIViewRepresentable {
    let content: SpotifyContentLink
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.uiDelegate = context.coordinator
        let html = """
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*{box-sizing:border-box}html,body,iframe{margin:0;width:100%;height:100%;border:0}</style>
        <iframe title="Lecteur Spotify" src="\(content.embedURL.absoluteString)"
                allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe>
        """
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url,
                  url.scheme == "https", let host = url.host?.lowercased(),
                  host == "spotify.com" || host.hasSuffix(".spotify.com") else { return nil }
            UIApplication.shared.open(url)
            return nil
        }
    }
}
