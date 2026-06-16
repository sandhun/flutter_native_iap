
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:native_iap/src/channel_constants.dart';
import 'package:native_iap/src/native_iap_models.dart';

/// Reusable client for native in-app purchase via method channel.
///
/// Use [instance] everywhere in the app so native events are delivered to one
/// handler. Call [install] once at startup with your product IDs; products are
/// fetched and cached automatically. Views read [products] or await [productsReady].
/// Subscribe to [events] for purchase callbacks.
class NativeIapChannel {
  NativeIapChannel._({String? channelName})
      : _channel = MethodChannel(channelName ?? kNativeIapChannelName);

  static NativeIapChannel? _instance;

  /// Shared app-wide instance. Native allows only one method-call handler.
  static NativeIapChannel get instance => _instance ??= NativeIapChannel._();

  final MethodChannel _channel;
  final StreamController<NativeIapEvent> _eventController =
      StreamController<NativeIapEvent>.broadcast();
  final StreamController<List<NativeIapProduct>> _productsController =
      StreamController<List<NativeIapProduct>>.broadcast();

  bool _installed = false;
  List<String> _productIds = const [];
  List<NativeIapProduct> _products = const [];
  bool _isLoadingProducts = false;
  Object? _productsError;
  Completer<List<NativeIapProduct>>? _productsReadyCompleter;

  /// Stream of events from native (purchase complete, failed, restored, etc.).
  Stream<NativeIapEvent> get events => _eventController.stream;

  /// Emits whenever the cached [products] list is updated.
  Stream<List<NativeIapProduct>> get productsStream => _productsController.stream;

  /// Cached store products. Empty until the first [install] fetch completes.
  List<NativeIapProduct> get products => _products;

  /// Whether a product fetch is in progress.
  bool get isLoadingProducts => _isLoadingProducts;

  /// Last product-fetch error, if any.
  Object? get productsError => _productsError;

  /// Completes when products have been loaded at least once.
  Future<List<NativeIapProduct>> get productsReady {
    if (_products.isNotEmpty || _productsError != null) {
      return Future.value(_products);
    }
    _productsReadyCompleter ??= Completer<List<NativeIapProduct>>();
    return _productsReadyCompleter!.future;
  }

  /// Look up a cached product by store identifier.
  NativeIapProduct? productById(String productId) {
    for (final product in _products) {
      if (product.productId == productId) return product;
    }
    return null;
  }

  /// Install the native handler and fetch [productIds] into [products].
  /// Call once during app startup.
  Future<void> install({required List<String> productIds}) async {
    if (!_installed) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _installed = true;
    }

    final ids = List<String>.unmodifiable(productIds);
    final sameIds = _listEquals(_productIds, ids);
    _productIds = ids;

    if (!sameIds || _products.isEmpty) {
      await refreshProducts();
    }
  }

  /// Re-fetch products configured in [install].
  Future<List<NativeIapProduct>> refreshProducts() async {
    if (_productIds.isEmpty) {
      _setProducts(const []);
      return _products;
    }

    _isLoadingProducts = true;
    _productsError = null;

    try {
      final fetched = await _fetchProductsFromNative(_productIds);
      _setProducts(fetched);
      return _products;
    } catch (error) {
      _productsError = error;
      _completeProductsReady();
      rethrow;
    } finally {
      _isLoadingProducts = false;
    }
  }

  void _setProducts(List<NativeIapProduct> products) {
    _products = List<NativeIapProduct>.unmodifiable(products);
    if (!_productsController.isClosed) {
      _productsController.add(_products);
    }
    _completeProductsReady();
  }

  void _completeProductsReady() {
    final completer = _productsReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(_products);
    }
    _productsReadyCompleter = null;
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

  Future<List<NativeIapProduct>> _fetchProductsFromNative(
    List<String> productIds,
  ) async {
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

  /// Release streams. Intended for tests; prefer keeping [instance] alive.
  void dispose() {
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    if (!_productsController.isClosed) {
      _productsController.close();
    }
    _channel.setMethodCallHandler(null);
    _installed = false;
    _productIds = const [];
    _products = const [];
    _isLoadingProducts = false;
    _productsError = null;
    _productsReadyCompleter = null;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
