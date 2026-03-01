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

// MARK: - StoreKit メッセージハンドラ
class StoreMessageHandler: NSObject, WKScriptMessageHandler {
    weak var viewModel: WebViewModel?

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

    func makeCoordinator() -> StoreMessageHandler {
        let handler = StoreMessageHandler()
        handler.viewModel = viewModel
        return handler
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

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        viewModel.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - ページロード完了後にプラン同期
extension StoreMessageHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel?.syncCurrentPlan()
    }
}
