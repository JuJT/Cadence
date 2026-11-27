import ExpoModulesCore
import PassKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CadenzaTransitWallet: NSObject, UIDocumentPickerDelegate {
    static let shared = CadenzaTransitWallet()

    private weak var presenter: UIViewController?
    private var pending: Promise?

    func choosePass(from presenter: UIViewController?, promise: Promise) {
        guard pending == nil, let presenter, PKAddPassesViewController.canAddPasses() else {
            promise.reject("WALLET_UNAVAILABLE", "Cartes est indisponible.")
            return
        }
        self.presenter = presenter
        self.pending = promise
        let format = UTType(filenameExtension: "pkpass") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [format], asCopy: true)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pending?.resolve(false)
        pending = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let promise = pending else { return }
        pending = nil
        guard let url = urls.first, url.pathExtension.lowercased() == "pkpass", let presenter else {
            promise.reject("INVALID_PASS", "Sélectionne un fichier officiel .pkpass.")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= 10 * 1024 * 1024,
                  let wallet = PKAddPassesViewController(pass: try PKPass(data: Data(contentsOf: url))) else {
                promise.reject("INVALID_PASS", "Cartes ne reconnaît pas ce titre.")
                return
            }
            let present = {
                presenter.present(wallet, animated: true) { promise.resolve(true) }
            }
            if controller.presentingViewController != nil {
                controller.dismiss(animated: true, completion: present)
            } else {
                present()
            }
        } catch {
            promise.reject("INVALID_PASS", "Cartes ne reconnaît pas ce titre.")
        }
    }
}
