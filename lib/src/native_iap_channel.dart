
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:native_iap/src/channel_constants.dart';
import 'package:native_iap/src/native_iap_models.dart';

/// Reusable client for native in-app purchase via method channel.
///
/// Use [instance] everywhere in the app so native events are delivered to one
/// handler. Call [install] once (e.g. from main), then use purchase/fetch APIs.
/// Subscribe to [events] to receive completion/failure/restore callbacks.
class NativeIapChannel {
  NativeIapChannel._({String? channelName})
      : _channel = MethodChannel(channelName ?? kNativeIapChannelName);

  static NativeIapChannel? _instance;

  /// Shared app-wide instance. Native allows only one method-call handler.
  static NativeIapChannel get instance => _instance ??= NativeIapChannel._();

  final MethodChannel _channel;
  final StreamController<NativeIapEvent> _eventController =
      StreamController<NativeIapEvent>.broadcast();

  bool _installed = false;

  /// Stream of events from native (purchase complete, failed, restored, etc.).
  Stream<NativeIapEvent> get events => _eventController.stream;

  /// Install the method call handler for native → Dart events.
  /// Call once during app startup.
  void install() {
    if (_installed) return;
    _channel.setMethodCallHandler(_handleMethodCall);
    _installed = true;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      final args = call.arguments as Map<Object?, Object?>?;
      final map = args != null ? Map<String, dynamic>.from(args) : <String, dynamic>{};

      switch (call.method) {
        case NativeIapEvents.onPurchaseComplete:
          _eventController.add(
            NativeIapPurchaseComplete(PurchaseCompleteResult.fromMap(args ?? {})),
          );
          break;
        case NativeIapEvents.onPurchaseFailed:
          _eventController.add(
            NativeIapPurchaseFailed(PurchaseFailedResult.fromMap(args ?? {})),
          );
          break;
        case NativeIapEvents.onPurchaseRestored:
          _eventController.add(
            NativeIapPurchaseRestored(PurchaseRestoredResult.fromMap(args ?? {})),
          );
          break;
        case NativeIapEvents.onPurchasePending:
          _eventController.add(
            NativeIapPurchasePending(
              productId: map['productId'] as String? ?? '',
            ),
          );
          break;
        case NativeIapEvents.onPurchaseAcknowledged:
          _eventController.add(
            NativeIapPurchaseAcknowledged(
              productId: map['productId'] as String? ?? '',
              purchaseToken: map['purchaseToken'] as String?,
            ),
          );
          break;
        case NativeIapEvents.onPurchaseDeferred:
          _eventController.add(
            NativeIapPurchaseDeferred(
              productId: map['productId'] as String? ?? '',
            ),
          );
          break;
        case NativeIapEvents.onPurchaseInProgress:
          _eventController.add(
            NativeIapPurchaseInProgress(
              productId: map['productId'] as String? ?? '',
            ),
          );
          break;
        default:
          break;
      }
    } catch (_) {}
    return null;
  }

  /// Start a subscription purchase (iOS: productId only; Android: productId + basePlanId).
  Future<void> purchaseSubscription({
    required String productId,
    String? basePlanId,
    String? applicationUsername,
  }) async {
    final args = <String, dynamic>{
      'productId': productId,
      if (basePlanId != null) 'basePlanId': basePlanId,
      if (applicationUsername != null) 'applicationUsername': applicationUsername,
    };
    await _channel.invokeMethod(NativeIapMethods.purchaseSubscription, args);
  }

  /// Purchase with an offer (Android: offerId; iOS: use [applyPromotionalOffer]).
  Future<void> purchaseSubscriptionOffer({
    required String productId,
    required String basePlanId,
    required String offerId,
    String? applicationUsername,
  }) async {
    final args = <String, dynamic>{
      'productId': productId,
      'basePlanId': basePlanId,
      'offerId': offerId,
      if (applicationUsername != null) 'applicationUsername': applicationUsername,
    };
    await _channel.invokeMethod(NativeIapMethods.purchaseSubscriptionOffer, args);
  }

  /// iOS-only: apply a promotional offer (signature from your backend).
  Future<void> applyPromotionalOffer({
    required String productId,
    required String offerId,
    required String signature,
    required String keyIdentifier,
    required String nonce,
    required int timestamp,
    String? applicationUsername,
  }) async {
    final args = <String, dynamic>{
      'productId': productId,
      'offerId': offerId,
      'signature': signature,
      'keyIdentifier': keyIdentifier,
      'nonce': nonce,
      'timestamp': timestamp,
      if (applicationUsername != null) 'applicationUsername': applicationUsername,
    };
    await _channel.invokeMethod(NativeIapMethods.applyPromotionalOffer, args);
  }

  /// Fetch subscription product metadata (title, price, base plans, etc.).
  Future<List<NativeIapProduct>> fetchProducts({
    required List<String> productIds,
  }) async {
    if (productIds.isEmpty) return const [];

    final result = await _channel.invokeMethod<List<Object?>>(
      NativeIapMethods.fetchProducts,
      {'productIds': productIds},
    );

    return (result ?? [])
        .map((e) => NativeIapProduct.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  /// Open platform subscription management (App Store / Play Store).
  Future<void> openSubscriptionSettings() async {
    await _channel.invokeMethod(NativeIapMethods.openSubscriptionSettings);
  }

  /// Restore previous purchases.
  Future<void> restorePurchases() async {
    await _channel.invokeMethod(NativeIapMethods.restorePurchases);
  }

  /// Release the event stream. Intended for tests; prefer keeping [instance] alive.
  void dispose() {
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    _channel.setMethodCallHandler(null);
    _installed = false;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
