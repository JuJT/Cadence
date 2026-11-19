import SwiftUI

struct AppUpdatesView: View {
    @State private var checking = false
    @State private var message: String?
    @State private var availableRelease: PublishedAppRelease?
    private var installedVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.5.0" }

    var body: some View {
        AtelierPage {
            AtelierCard {
                Image("CadenceMark").resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                Text("Cadenza").font(.title2.bold())
                Text("Version " + installedVersion).font(.subheadline).foregroundStyle(.secondary)
                Text("Retrouvez ici les nouvelles versions publiées.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let release = availableRelease {
                AtelierCard {
                    Label("Version " + release.tagName, systemImage: "arrow.down.circle").font(.headline)
                    Text("Une nouvelle version est disponible.")
                    Link("Voir la mise à jour", destination: release.htmlURL).frame(minHeight: 44)
                }
            }
            Button {
                Task { await check() }
            } label: {
                HStack {
                    if checking { ProgressView() }
                    Label(checking ? "Vérification…" : "Rechercher une mise à jour", systemImage: "arrow.clockwise")
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(checking)
                .accessibilityIdentifier("updates.check")
            if let message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("updates.status") }
            AtelierCard {
                Label("Votre installation", systemImage: "iphone.and.arrow.forward").font(.headline)
                Text("Avec Sideloadly, installez les nouvelles versions par-dessus Cadenza avec le même compte pour conserver votre suivi.")
                    .font(.subheadline)
                Text("Le renouvellement automatique de la signature se règle dans Sideloadly sur votre PC. Il nécessite que le PC puisse joindre l’iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("Mises à jour").navigationBarTitleDisplayMode(.large)
    }

    @MainActor private func check() async {
        guard !checking else { return }
        checking = true; message = nil; availableRelease = nil
        defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/JuJT/Cadence/releases/latest")!)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Cadenza/" + installedVersion, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 404 {
                message = "Aucune mise à jour publique n’est proposée pour le moment."
                return
            }
            guard response.statusCode == 200, data.count <= 1_000_000 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(PublishedAppRelease.self, from: data)
            guard !release.draft, !release.prerelease, release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
                  release.htmlURL.path.hasPrefix("/JuJT/Cadence/releases/") else { throw URLError(.badServerResponse) }
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            guard version.range(of: "^\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil else { throw URLError(.cannotParseResponse) }
            if version.compare(installedVersion, options: .numeric) == .orderedDescending { availableRelease = release }
            else { message = "Vous disposez de la dernière version publiée." }
        } catch {
            message = "La recherche n’a pas abouti. Vérifiez votre connexion puis réessayez."
        }
    }
}

private struct PublishedAppRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", draft, prerelease }
}
