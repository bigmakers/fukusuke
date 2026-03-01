import SwiftUI
import WebKit

class WebViewModel: ObservableObject {
    var webView: WKWebView?

    func importData(_ encodedData: String) {
        let js = "window.importFromURL('\(encodedData)');"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        viewModel.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
