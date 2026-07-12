import Cocoa
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // スタブ: 統合タスクで実装する。それまでは QL 標準フォールバックに落とす
        throw CocoaError(.featureUnsupported)
    }
}
