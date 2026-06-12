import Flutter
import StoreKit
import UIKit

public class NativeIapPlugin: NSObject, FlutterPlugin, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private static let channelName = "com.example.native_iap"

    private enum RequestMode {
        case purchase
        case promotional
        case fetch
    }

    private var requestMode: RequestMode = .purchase
    private var purchaseType = "regular"
    private var currentProductId: String?
    private var fetchResult: FlutterResult?
    private var currentApplicationUsername: String?
    private var currentOfferDetails: (
        offerId: String,
        keyIdentifier: String,
        nonce: UUID,
        signature: String,
        timestamp: UInt64,
        applicationUsername: String?
    )?
    private var flutterChannel: FlutterMethodChannel?
    private var resultHolder: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = NativeIapPlugin()
        instance.flutterChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        SKPaymentQueue.default().add(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "purchaseSubscription":
            guard let args = call.arguments as? [String: Any],
                  let productId = args["productId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "productId required", details: nil))
                return
            }
            let applicationUsername = args["applicationUsername"] as? String
            requestMode = .purchase
            purchaseType = "regular"
            currentProductId = productId
            currentApplicationUsername = applicationUsername
            let request = SKProductsRequest(productIdentifiers: [productId])
            request.delegate = self
            request.start()
            result(true)

        case "applyPromotionalOffer":
            guard let args = call.arguments as? [String: Any],
                  let productId = args["productId"] as? String,
                  let offerId = args["offerId"] as? String,
                  let signature = args["signature"] as? String,
                  let keyIdentifier = args["keyIdentifier"] as? String,
                  let nonceStr = args["nonce"] as? String,
                  let nonce = UUID(uuidString: nonceStr),
                  let timestamp = args["timestamp"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing offer parameters", details: nil))
                return
            }
            let applicationUsername = args["applicationUsername"] as? String
            requestMode = .promotional
            purchaseType = "promotional"
            currentProductId = productId
            currentApplicationUsername = applicationUsername
            currentOfferDetails = (
                offerId: offerId,
                keyIdentifier: keyIdentifier,
                nonce: nonce,
                signature: signature,
                timestamp: UInt64(timestamp),
                applicationUsername: applicationUsername
            )
            let request = SKProductsRequest(productIdentifiers: [productId])
            request.delegate = self
            request.start()
            result(true)

        case "openSubscriptionSettings":
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                result(true)
            } else {
                result(FlutterError(code: "INVALID_URL", message: "Could not create URL", details: nil))
            }

        case "restorePurchases":
            SKPaymentQueue.default().restoreCompletedTransactions()
            result(true)

        case "fetchProducts":
            guard let args = call.arguments as? [String: Any],
                  let productIds = args["productIds"] as? [String],
                  !productIds.isEmpty else {
                result(FlutterError(code: "INVALID_ARGS", message: "productIds required", details: nil))
                return
            }
            if fetchResult != nil {
                result(FlutterError(code: "IN_PROGRESS", message: "Product fetch already in progress", details: nil))
                return
            }
            requestMode = .fetch
            fetchResult = result
            let request = SKProductsRequest(productIdentifiers: Set(productIds))
            request.delegate = self
            request.start()

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - SKProductsRequestDelegate

    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if requestMode == .fetch {
            let products = response.products.map { product -> [String: Any] in
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceLocale
                let price = formatter.string(from: product.price) ?? "\(product.price)"
                return [
                    "productId": product.productIdentifier,
                    "title": product.localizedTitle,
                    "description": product.localizedDescription,
                    "price": price,
                    "rawPrice": product.price.doubleValue,
                    "currencyCode": product.priceLocale.currencyCode ?? "",
                    "subscriptionOffers": [] as [[String: Any]],
                ]
            }
            fetchResult?(products)
            fetchResult = nil
            requestMode = .purchase
            return
        }

        guard let product = response.products.first else {
            flutterChannel?.invokeMethod("onPurchaseFailed", arguments: ["error": "Product not found"])
            return
        }
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = currentApplicationUsername
        if purchaseType == "promotional", let offerDetails = currentOfferDetails {
            let discount = SKPaymentDiscount(
                identifier: offerDetails.offerId,
                keyIdentifier: offerDetails.keyIdentifier,
                nonce: offerDetails.nonce,
                signature: offerDetails.signature,
                timestamp: NSNumber(value: offerDetails.timestamp)
            )
            payment.paymentDiscount = discount
        }
        SKPaymentQueue.default().add(payment)
        currentProductId = nil
        currentApplicationUsername = nil
        if purchaseType == "promotional" { currentOfferDetails = nil }
        purchaseType = "regular"
    }

    public func request(_ request: SKRequest, didFailWithError error: Error) {
        if requestMode == .fetch {
            fetchResult?(FlutterError(code: "FETCH_FAILED", message: error.localizedDescription, details: nil))
            fetchResult = nil
            requestMode = .purchase
            return
        }

        flutterChannel?.invokeMethod("onPurchaseFailed", arguments: [
            "error": error.localizedDescription,
            "productId": currentProductId as Any,
        ])
        currentProductId = nil
        currentApplicationUsername = nil
        currentOfferDetails = nil
        requestMode = .purchase
        purchaseType = "regular"
    }

    // MARK: - SKPaymentTransactionObserver

    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                DispatchQueue.main.async { [weak self] in
                    let receipt = self?.fetchReceipt()
                    self?.flutterChannel?.invokeMethod("onPurchaseComplete", arguments: [
                        "productId": transaction.payment.productIdentifier,
                        "receipt": receipt as Any
                    ])
                }
                SKPaymentQueue.default().finishTransaction(transaction)

            case .failed:
                let errorMessage = transaction.error?.localizedDescription ?? "Unknown error"
                DispatchQueue.main.async { [weak self] in
                    self?.flutterChannel?.invokeMethod("onPurchaseFailed", arguments: [
                        "error": errorMessage,
                        "productId": transaction.payment.productIdentifier
                    ])
                }
                SKPaymentQueue.default().finishTransaction(transaction)

            case .restored:
                DispatchQueue.main.async { [weak self] in
                    let receipt = self?.fetchReceipt()
                    self?.flutterChannel?.invokeMethod("onPurchaseRestored", arguments: [
                        "productId": transaction.original?.payment.productIdentifier ?? "",
                        "receipt": receipt as Any
                    ])
                }
                SKPaymentQueue.default().finishTransaction(transaction)

            case .deferred:
                DispatchQueue.main.async { [weak self] in
                    self?.flutterChannel?.invokeMethod("onPurchaseDeferred", arguments: [
                        "productId": transaction.payment.productIdentifier
                    ])
                }

            case .purchasing:
                DispatchQueue.main.async { [weak self] in
                    self?.flutterChannel?.invokeMethod("onPurchaseInProgress", arguments: [
                        "productId": transaction.payment.productIdentifier
                    ])
                }

            @unknown default:
                break
            }
        }
    }

    private func fetchReceipt() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else { return nil }
        return receiptData.base64EncodedString()
    }
}
