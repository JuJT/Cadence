import CadenceCore
import CryptoKit
import SwiftUI

struct AppUpdatesView: View {
    @State private var checking = false
    @State private var message: String?
    @State private var availableRelease: AppRelease?
    @State private var downloading = false
    @State private var downloadedFile: URL?
    @State private var downloadError: String?

    private var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var installedVersionLabel: String {
        guard let installedVersion else { return "Version indisponible" }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(installedVersion) · build \($0)" } ?? "Version \(installedVersion)"
    }

    var body: some View {
        AtelierPage {
            AtelierCard {
                HStack(spacing: 12) {
                    Image("CadenceMark")
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cadenza").font(.title2.bold())
                        Text(installedVersionLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            if let availableRelease {
                releaseCard(availableRelease)
            }

            Button {
                Task { await check() }
            } label: {
                HStack {
                    if checking { ProgressView() }
                    Label(checking ? "Vérification…" : "Rechercher une mise à jour", systemImage: "arrow.clockwise")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(checking || downloading)
            .accessibilityIdentifier("updates.check")

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("updates.status")
            }

            AtelierCard {
                Label("Installation avec Sideloadly", systemImage: "iphone.and.arrow.forward").font(.headline)
                Text("Ouvrez l’IPA dans Sideloadly sur votre PC. Installez-la par-dessus Cadenza avec le même compte Apple et le même identifiant d’application. Conservez les extensions et le renouvellement automatique.")
                    .font(.subheadline)
                Text("Le PC signe l’application et doit pouvoir joindre votre iPhone pour l’installer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mises à jour")
        .navigationBarTitleDisplayMode(.large)
        .task { await check() }
    }

    private func releaseCard(_ release: AppRelease) -> some View {
        AtelierCard {
            Label("Cadenza \(release.version) disponible", systemImage: "arrow.down.circle")
                .font(.headline)
                .accessibilityIdentifier("updates.available")
            if let installer = release.installer {
                if let downloadedFile {
                    ShareLink(item: downloadedFile) {
                        Label("Enregistrer ou partager l’IPA", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task { await download(installer) }
                    } label: {
                        HStack {
                            if downloading { ProgressView() }
                            Label(downloading ? "Téléchargement…" : "Télécharger l’IPA", systemImage: "arrow.down.to.line")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(downloading || checking)
                    .accessibilityIdentifier("updates.download")
                }
                ShareLink(item: installer.url) {
                    Label("Partager le lien vers le PC", systemImage: "link")
                        .frame(minHeight: 44)
                }
                if let downloadError {
                    Text(downloadError).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("Cette version est publiée. Son fichier IPA n’est pas disponible.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let notes = release.notes {
                DisclosureGroup("Nouveautés") {
                    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    Text((try? AttributedString(markdown: notes, options: options)) ?? AttributedString(notes))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            Link("Ouvrir la version sur GitHub", destination: release.page).frame(minHeight: 44)
        }
    }

    @MainActor private func check() async {
        guard !checking, !downloading else { return }
        checking = true
        message = nil
        defer { checking = false }

        guard let installedVersion else {
            message = "Impossible de lire la version installée."
            return
        }
        do {
            var request = URLRequest(url: AppReleaseCheck.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Cadenza/" + installedVersion, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch try AppReleaseCheck.evaluate(status: response.statusCode, data: data, installedVersion: installedVersion) {
            case .noPublishedRelease:
                resetAvailableRelease()
                message = "Aucune version publique n’est disponible pour le moment."
            case .upToDate:
                resetAvailableRelease()
                message = "Cadenza est à jour."
            case .available(let release):
                if release != availableRelease { resetAvailableRelease() }
                availableRelease = release
            }
        } catch let error as URLError where error.code == .notConnectedToInternet {
            message = "Votre iPhone est hors ligne. Réessayez après avoir retrouvé votre connexion."
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            message = "Impossible de vérifier les mises à jour pour le moment. Réessayez dans quelques instants."
        }
    }

    @MainActor private func resetAvailableRelease() {
        availableRelease = nil
        downloadedFile = nil
        downloadError = nil
    }

    @MainActor private func download(_ installer: AppRelease.Installer) async {
        guard !downloading, !checking else { return }
        downloading = true
        downloadError = nil
        defer { downloading = false }
        do {
            downloadedFile = try await AppReleaseDownload.fetch(installer)
        } catch {
            downloadError = "Le téléchargement a échoué. Réessayez ou partagez le lien vers votre PC."
        }
    }
}

private enum AppReleaseDownload {
    static func fetch(_ installer: AppRelease.Installer) async throws -> URL {
        let (temporaryFile, response) = try await URLSession.shared.download(from: installer.url)
        defer { try? FileManager.default.removeItem(at: temporaryFile) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try temporaryFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) == installer.size else {
            throw URLError(.badServerResponse)
        }
        if let expectedDigest = installer.sha256, try sha256(of: temporaryFile) != expectedDigest {
            throw URLError(.cannotDecodeContentData)
        }
        let manager = FileManager.default
        let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CadenzaUpdates", isDirectory: true)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent(installer.name)
        if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        try manager.moveItem(at: temporaryFile, to: file)
        return file
    }

    private static func sha256(of file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hasher = SHA256()
        while let block = try input.read(upToCount: 128 * 1024), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
