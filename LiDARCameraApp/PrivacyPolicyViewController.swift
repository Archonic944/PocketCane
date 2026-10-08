import UIKit
import WebKit

// The same HTML files are bundled in the app and published in docs/.
final class PrivacyPolicyViewController: UIViewController, WKNavigationDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy Policy"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        view = webView
        if let url = Bundle.main.url(forResource: "privacy-policy", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL {
            decisionHandler(.allow)
        } else {
            // External policies open only after a deliberate link tap.
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    @objc private func close() {
        if let navigation = navigationController as? PrivacyNavigationController {
            navigation.close()
        } else {
            dismiss(animated: true)
        }
    }
}
