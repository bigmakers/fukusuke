import SwiftUI
import WebKit

class WebViewModel: ObservableObject {
    var webView: WKWebView?
    private var planObserver: NSObjectProtocol?

    init() {
        // プラン変更の監視
        planObserver = NotificationCenter.default.addObserver(
            forName: .planDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let plan = notification.userInfo?["plan"] as? String else { return }
            self?.syncPlan(plan)
        }
    }

    deinit {
        if let observer = planObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func importData(_ encodedData: String) {
        let js = "window.importFromURL('\(encodedData)');"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func syncPlan(_ planID: String) {
        let js = """
        localStorage.setItem('fukusuke_plan', '\(planID)');
        if (typeof renderGantt === 'function') renderGantt();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 初回ロード時にStoreKitのプラン状態をWebViewに同期
    func syncCurrentPlan() {
        Task { @MainActor in
            let plan = StoreManager.shared.currentPlan.rawValue
            syncPlan(plan)
        }
    }
}

// MARK: - Coordinator (Navigation + UI + Store)
class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var viewModel: WebViewModel?

    // MARK: - WKUIDelegate: alert()
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        topViewController()?.present(ac, animated: true)
    }

    // MARK: - WKUIDelegate: confirm()
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        topViewController()?.present(ac, animated: true)
    }

    // MARK: - WKUIDelegate: prompt()
    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        ac.addTextField { tf in tf.text = defaultText }
        ac.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(nil) })
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(ac.textFields?.first?.text)
        })
        topViewController()?.present(ac, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return nil }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    // MARK: - WKNavigationDelegate: ページロード完了
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel?.syncCurrentPlan()
    }

    // MARK: - WKScriptMessageHandler: StoreKit連携
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String],
              let action = body["action"] else { return }

        Task { @MainActor in
            switch action {
            case "purchase":
                guard let productIDStr = body["productId"],
                      let productID = ProductID(rawValue: productIDStr) else { return }
                let success = await StoreManager.shared.purchase(productID)
                if success {
                    let plan = StoreManager.shared.currentPlan.rawValue
                    let js = """
                    localStorage.setItem('fukusuke_plan', '\(plan)');
                    if (typeof updateUpgradeCards === 'function') updateUpgradeCards();
                    if (typeof updatePlanInfo === 'function') updatePlanInfo();
                    if (typeof renderGantt === 'function') renderGantt();
                    window._storeCallback && window._storeCallback({success: true, plan: '\(plan)'});
                    """
                    viewModel?.webView?.evaluateJavaScript(js, completionHandler: nil)
                } else {
                    let js = "window._storeCallback && window._storeCallback({success: false});"
                    viewModel?.webView?.evaluateJavaScript(js, completionHandler: nil)
                }

            case "restore":
                await StoreManager.shared.restorePurchases()
                let plan = StoreManager.shared.currentPlan.rawValue
                let js = """
                localStorage.setItem('fukusuke_plan', '\(plan)');
                if (typeof updateUpgradeCards === 'function') updateUpgradeCards();
                if (typeof updatePlanInfo === 'function') updatePlanInfo();
                if (typeof renderGantt === 'function') renderGantt();
                window._storeCallback && window._storeCallback({success: true, plan: '\(plan)', restored: true});
                """
                viewModel?.webView?.evaluateJavaScript(js, completionHandler: nil)

            case "getProducts":
                let products = StoreManager.shared.products.map { p in
                    ["id": p.id, "name": p.displayName, "price": p.displayPrice]
                }
                if let data = try? JSONSerialization.data(withJSONObject: products),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    let js = "window._productsCallback && window._productsCallback(\(jsonStr));"
                    viewModel?.webView?.evaluateJavaScript(js, completionHandler: nil)
                }

            default:
                break
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel

    func makeCoordinator() -> WebViewCoordinator {
        let coordinator = WebViewCoordinator()
        coordinator.viewModel = viewModel
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()

        // StoreKit メッセージハンドラ追加
        config.userContentController.add(context.coordinator, name: "store")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        viewModel.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
