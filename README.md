# native_iap

Reusable in-app purchase library using native **StoreKit** (iOS) and **BillingClient** (Android) via Flutter method channels.

## Structure

- **Dart** (`lib/`): Channel client and event stream API.
- **Android** (`android/`): `BillingClient` and method channel handler.
- **iOS** (`ios/`): StoreKit and method channel handler.

Channel name: `com.example.native_iap`.

## Usage

### 1. Add dependency

In your app `pubspec.yaml`:

```yaml
dependencies:
  native_iap:
    path: packages/native_iap
```

Run `flutter pub get`.

### 2. Use the Dart API

```dart
import 'package:native_iap/native_iap.dart';

// One-time setup (e.g. in main) — use the shared singleton everywhere
final nativeIap = NativeIapChannel.instance;
nativeIap.install();

// Listen for events (same instance from any screen/widget)
nativeIap.events.listen((event) {
  switch (event) {
    case NativeIapPurchaseComplete(:final result):
      // result.productId, result.receipt, result.purchaseToken
      break;
    case NativeIapPurchaseFailed(:final result):
      // result.error, result.productId
      break;
    case NativeIapPurchaseRestored(:final result):
      break;
    case NativeIapPurchasePending(:final productId):
      break;
    case NativeIapPurchaseAcknowledged():
      break;
    case NativeIapPurchaseDeferred():
      break;
    case NativeIapPurchaseInProgress():
      break;
  }
});

// Fetch product metadata for your paywall
final products = await nativeIap.fetchProducts(
  productIds: ['com.example.subscription'],
);
for (final product in products) {
  // product.title, product.price, product.currencyCode
  // Android: product.subscriptionOffers (basePlanId, offerId, price, ...)
}

// Purchase (iOS: productId only; Android: productId + basePlanId)
await nativeIap.purchaseSubscription(
  productId: 'com.example.subscription',
  basePlanId: 'monthly',  // Android only
  applicationUsername: null,  // optional
);

// Android offer / iOS promotional offer
await nativeIap.purchaseSubscriptionOffer(
  productId: '...',
  basePlanId: '...',
  offerId: '...',
  applicationUsername: null,  // optional
);
// iOS: use applyPromotionalOffer(...) with signature from your backend

await nativeIap.openSubscriptionSettings();
await nativeIap.restorePurchases();
```

## Method / event reference

| Dart → Native        | Description                    |
|----------------------|--------------------------------|
| `fetchProducts` | Query subscription metadata for product IDs |
| `purchaseSubscription` | Start subscription (productId; Android: basePlanId) |
| `purchaseSubscriptionOffer` | Start subscription with offer (Android) |
| `applyPromotionalOffer` | iOS promotional offer (signature from backend) |
| `openSubscriptionSettings` | Open App Store / Play Store subscription management |
| `restorePurchases`   | Restore previous purchases     |

| Native → Dart (events) | Payload |
|------------------------|--------|
| `onPurchaseComplete`   | productId, receipt (iOS), purchaseToken (Android) |
| `onPurchaseFailed`     | error, productId?, code? |
| `onPurchaseRestored`   | productId, receipt?, purchaseToken? |
| `onPurchasePending`    | productId (Android) |
| `onPurchaseAcknowledged` | productId, purchaseToken? (Android) |
| `onPurchaseDeferred`   | productId (iOS) |
| `onPurchaseInProgress` | productId (iOS) |
