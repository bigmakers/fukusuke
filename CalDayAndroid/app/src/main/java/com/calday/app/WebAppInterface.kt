package com.calday.app

import android.webkit.JavascriptInterface
import org.json.JSONObject

/**
 * JavaScript interface for communication between WebView and native Android.
 * Handles StoreKit-compatible messages from the HTML/JS code.
 */
class WebAppInterface(
    private val activity: MainActivity,
    private val billingManager: BillingManager
) {

    /**
     * Receives messages from JavaScript in the same format as iOS WKScriptMessageHandler.
     * Called via: AndroidBridge.postMessage(JSON.stringify({action: "purchase", productId: "..."}))
     */
    @JavascriptInterface
    fun postMessage(jsonString: String) {
        try {
            val json = JSONObject(jsonString)
            val action = json.optString("action", "")

            when (action) {
                "purchase" -> {
                    val productId = json.optString("productId", "")
                    if (productId.isNotEmpty()) {
                        billingManager.purchase(productId)
                    }
                }

                "restore" -> {
                    billingManager.restorePurchases()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Called from BillingManager when a purchase completes successfully.
     */
    fun onPurchaseSuccess(plan: String) {
        val js = """
            localStorage.setItem('fukusuke_plan', '$plan');
            if (typeof updateUpgradeCards === 'function') updateUpgradeCards();
            if (typeof updatePlanInfo === 'function') updatePlanInfo();
            if (typeof renderGantt === 'function') renderGantt();
            window._storeCallback && window._storeCallback({success: true, plan: '$plan'});
        """.trimIndent()
        activity.runOnUiThread {
            activity.webView.evaluateJavascript(js, null)
        }
    }

    /**
     * Called from BillingManager when a restore completes successfully.
     */
    fun onRestoreSuccess(plan: String) {
        val js = """
            localStorage.setItem('fukusuke_plan', '$plan');
            if (typeof updateUpgradeCards === 'function') updateUpgradeCards();
            if (typeof updatePlanInfo === 'function') updatePlanInfo();
            if (typeof renderGantt === 'function') renderGantt();
            window._storeCallback && window._storeCallback({success: true, plan: '$plan', restored: true});
        """.trimIndent()
        activity.runOnUiThread {
            activity.webView.evaluateJavascript(js, null)
        }
    }
}
