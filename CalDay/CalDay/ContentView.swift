import SwiftUI

struct ContentView: View {
    @StateObject private var webViewModel = WebViewModel()

    var body: some View {
        WebView(viewModel: webViewModel)
            .ignoresSafeArea(.container, edges: .bottom)
            .onOpenURL { url in
                handleURL(url)
            }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "calday",
              url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let data = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { return }

        // WebViewがロード済みなら即実行、まだなら少し待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            webViewModel.importData(data)
        }
    }
}
