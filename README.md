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

// One-time setup in main — installs handler and fetches products into cache
final nativeIap = NativeIapChannel.instance;
await nativeIap.install(
  productIds: ['com.example.subscription'],
);

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

// Any view can read cached products (no extra fetch call)
final products = nativeIap.products;
final subscription = nativeIap.productById('com.example.subscription');
// subscription?.title, subscription?.price

// Or wait / listen for the first load
await nativeIap.productsReady;
nativeIap.productsStream.listen((products) {
  // rebuild paywall when products refresh
});

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
| `install` | Install handler and fetch/cache product IDs |
| `refreshProducts` | Re-fetch products configured in `install` |
| `products` / `productsReady` / `productsStream` | Read cached product metadata from any view |
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
