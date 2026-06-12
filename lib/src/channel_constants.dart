
/// Method channel name used for native in-app purchase communication.
/// Use this when configuring the app's native side to match.
const String kNativeIapChannelName = 'com.example.native_iap';

/// Method names: Dart → Native
abstract final class NativeIapMethods {
  static const String purchaseSubscription = 'purchaseSubscription';
  static const String purchaseSubscriptionOffer = 'purchaseSubscriptionOffer';
  static const String applyPromotionalOffer = 'applyPromotionalOffer';
  static const String openSubscriptionSettings = 'openSubscriptionSettings';
  static const String restorePurchases = 'restorePurchases';
  static const String fetchProducts = 'fetchProducts';
}


/// Event names: Native → Dart
abstract final class NativeIapEvents {
  static const String onPurchaseComplete = 'onPurchaseComplete';
  static const String onPurchaseFailed = 'onPurchaseFailed';
  static const String onPurchaseRestored = 'onPurchaseRestored';
  static const String onPurchasePending = 'onPurchasePending';
  static const String onPurchaseAcknowledged = 'onPurchaseAcknowledged';
  static const String onPurchaseDeferred = 'onPurchaseDeferred';
  static const String onPurchaseInProgress = 'onPurchaseInProgress';
}
