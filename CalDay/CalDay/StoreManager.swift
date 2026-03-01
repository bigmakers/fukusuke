import Foundation
import StoreKit

/// アプリ内課金のプロダクトID
enum ProductID: String, CaseIterable {
    case basic = "com.calday.app.basic"      // ¥300 - 10件まで
    case premium = "com.calday.app.premium"   // ¥1,200 - 無制限
}

/// プラン情報
enum PlanType: String {
    case free = "free"
    case basic = "basic"
    case premium = "premium"
}

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 現在のプラン取得

    var currentPlan: PlanType {
        if purchasedProductIDs.contains(ProductID.premium.rawValue) {
            return .premium
        } else if purchasedProductIDs.contains(ProductID.basic.rawValue) {
            return .basic
        }
        return .free
    }

    var maxEntries: Int {
        switch currentPlan {
        case .free: return 3
        case .basic: return 10
        case .premium: return Int.max
        }
    }

    // MARK: - プロダクト読み込み

    func loadProducts() async {
        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - 購入処理

    func purchase(_ productID: ProductID) async -> Bool {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                return true

            case .userCancelled:
                return false

            case .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            print("Purchase failed: \(error)")
            return false
        }
    }

    // MARK: - 購入復元

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - トランザクション監視

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - 購入状態更新

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("Entitlement verification failed: \(error)")
            }
        }

        purchasedProductIDs = purchased

        // WebView側のlocalStorageと同期
        syncPlanToLocalStorage()
    }

    // MARK: - WebView連携

    /// WebView側のlocalStorageにプラン情報を同期するためのJS文字列を返す
    func planSyncJavaScript() -> String {
        let planID = currentPlan.rawValue
        return "localStorage.setItem('fukusuke_plan', '\(planID)');"
    }

    private func syncPlanToLocalStorage() {
        // ContentViewのWebViewModel経由で呼ぶ
        NotificationCenter.default.post(
            name: .planDidChange,
            object: nil,
            userInfo: ["plan": currentPlan.rawValue]
        )
    }

    // MARK: - 検証ヘルパー

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - エラー型

enum StoreError: Error {
    case failedVerification
}

// MARK: - Notification

extension Notification.Name {
    static let planDidChange = Notification.Name("planDidChange")
}
