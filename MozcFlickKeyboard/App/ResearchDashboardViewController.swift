import UIKit
import WebKit
import MozcFlickShared

/// Same-origin research UI served over the existing private Tailscale connection.
final class ResearchDashboardViewController: UIViewController, WKNavigationDelegate, WKDownloadDelegate {
    private let webView = WKWebView(frame: .zero)
    private var allowedHost: String?
    private var exportURL: URL?
    override func loadView() { view = webView; webView.navigationDelegate = self }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "生活状態の研究"
        let state = NarrativeState()
        guard var root = URL(string: state.backendBaseURL), ["http", "https"].contains(root.scheme ?? "") else { return }
        root.appendPathComponent("research"); root.appendPathComponent(state.participantID)
        allowedHost = root.host; webView.load(URLRequest(url: root))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = action.request.url, url.host == allowedHost || url.scheme == "blob" else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lifelog-all-\(UUID().uuidString).json")
        exportURL = url; completionHandler(url)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let url = exportURL else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        present(share, animated: true)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { showError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }
    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "接続・保存を確認してください", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .cancel)); present(alert, animated: true)
    }
}
