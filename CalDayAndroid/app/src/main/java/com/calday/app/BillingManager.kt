package com.calday.app

import com.android.billingclient.api.*
import kotlinx.coroutines.*

/**
 * Manages Google Play Billing for in-app purchases.
 *
 * Products (same IDs as iOS):
 *   - com.calday.app.basic   → "basic" plan (10 entries)
 *   - com.calday.app.premium → "premium" plan (unlimited)
 */
class BillingManager(
    private val activity: MainActivity
) : PurchasesUpdatedListener {

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val billingClient: BillingClient = BillingClient.newBuilder(activity)
        .setListener(this)
        .enablePendingPurchases()
        .build()

    private var productDetails: Map<String, ProductDetails> = emptyMap()

    var webAppInterface: WebAppInterface? = null

    init {
        connectAndLoadProducts()
    }

    private fun connectAndLoadProducts() {
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    loadProducts()
                    checkExistingPurchases()
                }
            }

            override fun onBillingServiceDisconnected() {
                scope.launch {
                    delay(3000)
                    connectAndLoadProducts()
                }
            }
        })
    }

    private fun loadProducts() {
        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId("com.calday.app.basic")
                .setProductType(BillingClient.ProductType.INAPP)
                .build(),
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId("com.calday.app.premium")
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        )

        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()

        billingClient.queryProductDetailsAsync(params) { result, details ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                productDetails = details.associateBy { it.productId }
            }
        }
    }

    fun purchase(productId: String) {
        val details = productDetails[productId]
        if (details == null) {
            // Fallback for debug/testing when billing is not available
            val plan = productIdToPlan(productId)
            webAppInterface?.onPurchaseSuccess(plan)
            return
        }

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .build()
                )
            )
            .build()

        billingClient.launchBillingFlow(activity, flowParams)
    }

    fun restorePurchases() {
        checkExistingPurchases()
    }

    private fun checkExistingPurchases() {
        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        ) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                var bestPlan = "free"
                for (purchase in purchases) {
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        if (!purchase.isAcknowledged) {
                            acknowledgePurchase(purchase)
                        }
                        val plan = purchaseToPlan(purchase)
                        if (planRank(plan) > planRank(bestPlan)) {
                            bestPlan = plan
                        }
                    }
                }
                if (bestPlan != "free") {
                    webAppInterface?.onRestoreSuccess(bestPlan)
                }
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (purchase in purchases) {
                if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                    acknowledgePurchase(purchase)
                    val plan = purchaseToPlan(purchase)
                    webAppInterface?.onPurchaseSuccess(plan)
                }
            }
        }
    }

    private fun acknowledgePurchase(purchase: Purchase) {
        if (purchase.isAcknowledged) return
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        billingClient.acknowledgePurchase(params) { }
    }

    private fun purchaseToPlan(purchase: Purchase): String {
        return when {
            purchase.products.contains("com.calday.app.premium") -> "premium"
            purchase.products.contains("com.calday.app.basic") -> "basic"
            else -> "free"
        }
    }

    private fun productIdToPlan(productId: String): String {
        return when (productId) {
            "com.calday.app.premium" -> "premium"
            "com.calday.app.basic" -> "basic"
            else -> "free"
        }
    }

    private fun planRank(plan: String): Int {
        return when (plan) {
            "premium" -> 2
            "basic" -> 1
            else -> 0
        }
    }

    fun destroy() {
        scope.cancel()
        billingClient.endConnection()
    }
}
