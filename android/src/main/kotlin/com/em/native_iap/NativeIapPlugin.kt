package com.em.native_iap

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchaseHistoryParams
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class NativeIapPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PurchasesUpdatedListener {

    private val channelName = "com.example.native_iap"
    private val tag = "NativeIapPlugin"

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private lateinit var billingClient: BillingClient
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, channelName)
        channel!!.setMethodCallHandler(this)
        setupBillingClient(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        scope.coroutineContext[Job]?.cancel()
        if (::billingClient.isInitialized) {
            billingClient.endConnection()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun setupBillingClient(context: android.content.Context) {
        billingClient = BillingClient.newBuilder(context)
            .setListener(this)
            .enablePendingPurchases()
            .build()

        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    Log.d(tag, "Billing client connected")
                } else {
                    Log.e(tag, "Billing setup failed: ${billingResult.debugMessage}")
                }
            }

            override fun onBillingServiceDisconnected() {
                Log.w(tag, "Billing disconnected")
                scope.launch {
                    delay(1000)
                    setupBillingClient(context)
                }
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "openSubscriptionSettings" -> {
                try {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("https://play.google.com/store/account/subscriptions")
                        setPackage("com.android.vending")
                    }
                    activity?.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to open subscription settings", e.message)
                }
            }
            "purchaseSubscription" -> {
                val productId = call.argument<String>("productId")
                val basePlanId = call.argument<String>("basePlanId")
                val applicationUsername = call.argument<String>("applicationUsername")
                if (productId == null || basePlanId == null) {
                    result.error("ERROR", "Missing productId or basePlanId", null)
                    return
                }
                scope.launch {
                    try {
                        val success = purchaseSubscription(productId, basePlanId, applicationUsername)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to purchase subscription", e.message)
                    }
                }
            }
            "purchaseSubscriptionOffer" -> {
                val productId = call.argument<String>("productId")
                val basePlanId = call.argument<String>("basePlanId")
                val offerId = call.argument<String>("offerId")
                val applicationUsername = call.argument<String>("applicationUsername")
                if (productId == null || basePlanId == null || offerId == null) {
                    result.error("ERROR", "Missing required parameters", null)
                    return
                }
                scope.launch {
                    try {
                        val success = purchaseSubscriptionOffer(productId, basePlanId, offerId, applicationUsername)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to purchase subscription offer", e.message)
                    }
                }
            }
            "restorePurchases" -> {
                scope.launch {
                    try {
                        restorePurchases()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to restore purchases", e.message)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases?.forEach { purchase ->
                    when (purchase.purchaseState) {
                        Purchase.PurchaseState.PURCHASED -> {
                            scope.launch { handlePurchase(purchase) }
                            activity?.runOnUiThread {
                                channel?.invokeMethod("onPurchaseComplete", mapOf(
                                    "productId" to purchase.products[0],
                                    "purchaseToken" to purchase.purchaseToken
                                ))
                            }
                        }
                        Purchase.PurchaseState.PENDING -> {
                            activity?.runOnUiThread {
                                channel?.invokeMethod("onPurchasePending", mapOf(
                                    "productId" to purchase.products[0]
                                ))
                            }
                        }
                        else -> {}
                    }
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                activity?.runOnUiThread {
                    channel?.invokeMethod("onPurchaseFailed", mapOf(
                        "error" to "Purchase cancelled by user"
                    ))
                }
            }
            else -> {
                activity?.runOnUiThread {
                    channel?.invokeMethod("onPurchaseFailed", mapOf(
                        "error" to billingResult.debugMessage,
                        "code" to billingResult.responseCode.toString()
                    ))
                }
            }
        }
    }

    private suspend fun handlePurchase(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (!purchase.isAcknowledged) {
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            withContext(Dispatchers.IO) {
                val ackResult = suspendCoroutine<BillingResult> { cont ->
                    billingClient.acknowledgePurchase(params) { cont.resume(it) }
                }
                if (ackResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    activity?.runOnUiThread {
                        channel?.invokeMethod("onPurchaseAcknowledged", mapOf(
                            "productId" to purchase.products[0],
                            "purchaseToken" to purchase.purchaseToken
                        ))
                    }
                } else {
                    activity?.runOnUiThread {
                        channel?.invokeMethod("onPurchaseFailed", mapOf(
                            "error" to "Acknowledge failed: ${ackResult.debugMessage}",
                            "productId" to purchase.products[0]
                        ))
                    }
                }
            }
        }
    }

    private suspend fun purchaseSubscription(
        productId: String,
        basePlanId: String,
        applicationUsername: String?
    ): Boolean = withContext(Dispatchers.IO) {
        val queryParams = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                )
            )
            .build()

        val (billingResult, productDetailsList) = suspendCoroutine<Pair<BillingResult, List<ProductDetails>>> { cont ->
            billingClient.queryProductDetailsAsync(queryParams) { result, list ->
                cont.resume(result to (list ?: emptyList()))
            }
        }

        if (productDetailsList.isEmpty()) throw Exception("Product not found")
        val productDetails = productDetailsList[0]
        val offer = productDetails.subscriptionOfferDetails?.find {
            it.basePlanId == basePlanId && it.offerId == null
        } ?: throw Exception("Base plan not found")

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .setOfferToken(offer.offerToken)
                        .build()
                )
            )
            .apply {
                applicationUsername?.let { setObfuscatedAccountId(it) }
            }
            .build()

        val act = activity ?: throw Exception("Activity not available")
        val flowResult = billingClient.launchBillingFlow(act, flowParams)
        flowResult.responseCode == BillingClient.BillingResponseCode.OK
    }

    private suspend fun purchaseSubscriptionOffer(
        productId: String,
        basePlanId: String,
        offerId: String,
        applicationUsername: String?
    ): Boolean = withContext(Dispatchers.IO) {
        val queryParams = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                )
            )
            .build()

        val (_, productDetailsList) = suspendCoroutine<Pair<BillingResult, List<ProductDetails>>> { cont ->
            billingClient.queryProductDetailsAsync(queryParams) { result, list ->
                cont.resume(result to (list ?: emptyList()))
            }
        }

        if (productDetailsList.isEmpty()) throw Exception("Product not found")
        val productDetails = productDetailsList[0]
        val offer = productDetails.subscriptionOfferDetails?.find {
            it.basePlanId == basePlanId && it.offerId == offerId
        } ?: throw Exception("Offer not found")

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .setOfferToken(offer.offerToken)
                        .build()
                )
            )
            .apply {
                applicationUsername?.let { setObfuscatedAccountId(it) }
            }
            .build()

        val act = activity ?: throw Exception("Activity not available")
        val flowResult = billingClient.launchBillingFlow(act, flowParams)
        flowResult.responseCode == BillingClient.BillingResponseCode.OK
    }

    private suspend fun restorePurchases() = withContext(Dispatchers.IO) {
        val params = QueryPurchaseHistoryParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        val result = suspendCoroutine<BillingResult> { cont ->
            billingClient.queryPurchaseHistoryAsync(params) { billingResult, records ->
                records?.forEach { record ->
                    activity?.runOnUiThread {
                        channel?.invokeMethod("onPurchaseRestored", mapOf(
                            "productId" to record.products[0],
                            "purchaseToken" to record.purchaseToken
                        ))
                    }
                }
                cont.resume(billingResult)
            }
        }
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            throw Exception("Restore failed: ${result.debugMessage}")
        }
    }
}
