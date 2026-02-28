
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:native_iap/src/channel_constants.dart';
import 'package:native_iap/src/native_iap_models.dart';

/// Reusable client for native in-app purchase via method channel.
///
/// Call [install] once (e.g. from your payment controller or main),
/// then use [purchaseSubscription], [purchaseSubscriptionOffer], etc.
/// Subscribe to [events] to receive completion/failure/restore callbacks.
class NativeIapChannel {
  NativeIapChannel({String? channelName})
      : _channel = MethodChannel(channelName ?? kNativeIapChannelName);

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

  /// Open platform subscription management (App Store / Play Store).
  Future<void> openSubscriptionSettings() async {
    await _channel.invokeMethod(NativeIapMethods.openSubscriptionSettings);
  }

  /// Restore previous purchases.
  Future<void> restorePurchases() async {
    await _channel.invokeMethod(NativeIapMethods.restorePurchases);
  }

  /// Release the event stream. Call when shutting down.
  void dispose() {
    _eventController.close();
  }
}
