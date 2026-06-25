import Flutter
import StoreKit
import UIKit

public class NativeIapPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.example.native_iap"

    private var flutterChannel: FlutterMethodChannel?
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = NativeIapPlugin()
        instance.flutterChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.startTransactionListener()
    }

    /// Listens for transactions that arrive outside of a direct purchase call —
    /// renewals, family-sharing grants, interrupted purchases, etc.
    private func startTransactionListener() {
        transactionListenerTask = Task { [weak self] in
            for await verificationResult in Transaction.updates {
                await self?.dispatchTransactionUpdate(verificationResult)
            }
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Method channel dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "fetchProducts":
            handleFetchProducts(call, result: result)
        case "purchaseSubscription":
            handlePurchaseSubscription(call, result: result)
        case "applyPromotionalOffer":
            handleApplyPromotionalOffer(call, result: result)
        case "openSubscriptionSettings":
            handleOpenSubscriptionSettings(result: result)
        case "restorePurchases":
            handleRestorePurchases(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - fetchProducts

    private func handleFetchProducts(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let productIds = args["productIds"] as? [String],
              !productIds.isEmpty else {
            result(FlutterError(code: "INVALID_ARGS", message: "productIds required", details: nil))
            return
        }
        Task {
            do {
                let products = try await Product.products(for: productIds)
                let mapped = products.map { mapProduct($0) }
                await MainActor.run { result(mapped) }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "FETCH_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func mapProduct(_ product: Product) -> [String: Any] {
        let currencyCode = product.priceFormatStyle.currencyCode
        var offers: [[String: Any]] = []
        if let intro = product.subscription?.introductoryOffer {
            offers.append(mapSubscriptionOffer(intro, currencyCode: currencyCode))
        }
        for promo in product.subscription?.promotionalOffers ?? [] {
            offers.append(mapSubscriptionOffer(promo, currencyCode: currencyCode))
        }
        return [
            "productId": product.id,
            "title": product.displayName,
            "description": product.description,
            "price": product.displayPrice,
            "rawPrice": NSDecimalNumber(decimal: product.price).doubleValue,
            "currencyCode": currencyCode,
            "subscriptionOffers": offers,
        ]
    }

    private func mapSubscriptionOffer(
        _ offer: Product.SubscriptionOffer,
        currencyCode: String
    ) -> [String: Any] {
        return [
            "basePlanId": "",
            "offerId": offer.id ?? "",
            "price": offer.displayPrice,
            "rawPrice": NSDecimalNumber(decimal: offer.price).doubleValue,
            "currencyCode": currencyCode,
            "billingPeriod": isoPeriodString(offer.period),
            "offerToken": "",
        ]
    }

    private func isoPeriodString(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day:   return "P\(n)D"
        case .week:  return "P\(n)W"
        case .month: return "P\(n)M"
        case .year:  return "P\(n)Y"
        @unknown default: return "P\(n)D"
        }
    }

    // MARK: - purchaseSubscription

    private func handlePurchaseSubscription(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let productId = args["productId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "productId required", details: nil))
            return
        }
        let applicationUsername = args["applicationUsername"] as? String
        // Return immediately; outcome arrives as a channel event.
        result(true)
        Task { @MainActor [weak self] in
            await self?.purchaseProduct(
                productId: productId,
                applicationUsername: applicationUsername,
                extraOptions: []
            )
        }
    }

    // MARK: - applyPromotionalOffer

    private func handleApplyPromotionalOffer(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let productId       = args["productId"]       as? String,
              let offerId         = args["offerId"]         as? String,
              let signatureStr    = args["signature"]       as? String,
              let keyIdentifier   = args["keyIdentifier"]   as? String,
              let nonceStr        = args["nonce"]           as? String,
              let nonce           = UUID(uuidString: nonceStr),
              let timestamp       = args["timestamp"]       as? Int,
              let signatureData   = Data(base64Encoded: signatureStr) else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing or invalid promotional offer parameters",
                details: nil
            ))
            return
        }
        let applicationUsername = args["applicationUsername"] as? String
        result(true)
        Task { @MainActor [weak self] in
            let promoOption = Product.PurchaseOption.promotionalOffer(
                offerID: offerId,
                keyID: keyIdentifier,
                nonce: nonce,
                signature: signatureData,
                timestamp: timestamp
            )
            await self?.purchaseProduct(
                productId: productId,
                applicationUsername: applicationUsername,
                extraOptions: [promoOption]
            )
        }
    }

    // MARK: - Purchase core

    @MainActor
    private func purchaseProduct(
        productId: String,
        applicationUsername: String?,
        extraOptions: [Product.PurchaseOption]
    ) async {
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                sendEvent("onPurchaseFailed", arguments: [
                    "error": "Product not found",
                    "productId": productId,
                ])
                return
            }

            var options = Set(extraOptions)
            if let username = applicationUsername, let uuid = UUID(uuidString: username) {
                options.insert(.appAccountToken(uuid))
            }

            let purchaseResult = try await product.purchase(options: options)
            await handlePurchaseResult(purchaseResult, productId: productId)
        } catch {
            sendEvent("onPurchaseFailed", arguments: [
                "error": error.localizedDescription,
                "productId": productId,
            ])
        }
    }

    @MainActor
    private func handlePurchaseResult(_ purchaseResult: Product.PurchaseResult, productId: String) async {
        switch purchaseResult {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                sendEvent("onPurchaseComplete", arguments: [
                    "productId": transaction.productID,
                    "receipt": verificationResult.jwsRepresentation,
                ])
                await transaction.finish()
            case .unverified(let transaction, let verificationError):
                sendEvent("onPurchaseFailed", arguments: [
                    "error": "Verification failed: \(verificationError.localizedDescription)",
                    "productId": transaction.productID,
                ])
                await transaction.finish()
            }
        case .userCancelled:
            sendEvent("onPurchaseFailed", arguments: [
                "error": "User cancelled",
                "productId": productId,
            ])
        case .pending:
            sendEvent("onPurchaseDeferred", arguments: ["productId": productId])
        @unknown default:
            break
        }
    }

    // MARK: - Transaction.updates listener

    private func dispatchTransactionUpdate(_ verificationResult: VerificationResult<Transaction>) async {
        switch verificationResult {
        case .verified(let transaction):
            await MainActor.run {
                sendEvent("onPurchaseComplete", arguments: [
                    "productId": transaction.productID,
                    "receipt": verificationResult.jwsRepresentation,
                ])
            }
            await transaction.finish()
        case .unverified(let transaction, _):
            // Finish unverified transactions without surfacing them.
            await transaction.finish()
        }
    }

    // MARK: - restorePurchases

    private func handleRestorePurchases(result: @escaping FlutterResult) {
        result(true)
        Task {
            for await verificationResult in Transaction.currentEntitlements {
                if case .verified(let transaction) = verificationResult {
                    await MainActor.run { [weak self] in
                        self?.sendEvent("onPurchaseRestored", arguments: [
                            "productId": transaction.productID,
                            "receipt": verificationResult.jwsRepresentation,
                        ])
                    }
                }
            }
        }
    }

    // MARK: - openSubscriptionSettings

    private func handleOpenSubscriptionSettings(result: @escaping FlutterResult) {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            result(FlutterError(code: "INVALID_URL", message: "Could not create URL", details: nil))
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        result(true)
    }

    // MARK: - Helpers

    /// Must be called on the main actor (FlutterMethodChannel is not thread-safe).
    @MainActor
    private func sendEvent(_ method: String, arguments: [String: Any]) {
        flutterChannel?.invokeMethod(method, arguments: arguments)
    }
}
