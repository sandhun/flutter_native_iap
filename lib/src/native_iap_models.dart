/// A subscription offer / base plan (primarily Android; iOS uses product-level pricing).
class NativeIapSubscriptionOffer {
  const NativeIapSubscriptionOffer({
    required this.basePlanId,
    this.offerId,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.billingPeriod,
    this.offerToken,
  });

  factory NativeIapSubscriptionOffer.fromMap(Map<Object?, Object?> map) {
    final m = Map<String, dynamic>.from(map as Map);
    return NativeIapSubscriptionOffer(
      basePlanId: m['basePlanId'] as String? ?? '',
      offerId: m['offerId'] as String?,
      price: m['price'] as String? ?? '',
      rawPrice: (m['rawPrice'] as num?)?.toDouble() ?? 0,
      currencyCode: m['currencyCode'] as String? ?? '',
      billingPeriod: m['billingPeriod'] as String?,
      offerToken: m['offerToken'] as String?,
    );
  }

  final String basePlanId;
  final String? offerId;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final String? billingPeriod;
  final String? offerToken;
}

/// Store product metadata returned by [NativeIapChannel.fetchProducts].
class NativeIapProduct {
  const NativeIapProduct({
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.subscriptionOffers = const [],
  });

  factory NativeIapProduct.fromMap(Map<Object?, Object?> map) {
    final m = Map<String, dynamic>.from(map as Map);
    final offersRaw = m['subscriptionOffers'] as List<Object?>? ?? [];
    return NativeIapProduct(
      productId: m['productId'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      price: m['price'] as String? ?? '',
      rawPrice: (m['rawPrice'] as num?)?.toDouble() ?? 0,
      currencyCode: m['currencyCode'] as String? ?? '',
      subscriptionOffers: offersRaw
          .map(
            (e) => NativeIapSubscriptionOffer.fromMap(e as Map<Object?, Object?>),
          )
          .toList(),
    );
  }

  final String productId;
  final String title;
  final String description;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final List<NativeIapSubscriptionOffer> subscriptionOffers;
}

/// Result of a completed purchase (iOS receipt or Android purchase token).
class PurchaseCompleteResult {
  const PurchaseCompleteResult({
    required this.productId,
    this.purchaseToken,
    this.receipt,
  });

  factory PurchaseCompleteResult.fromMap(Map<Object?, Object?> map) {
    final m = Map<String, dynamic>.from(map as Map);
    return PurchaseCompleteResult(
      productId: m['productId'] as String? ?? '',
      purchaseToken: m['purchaseToken'] as String?,
      receipt: m['receipt'] as String?,
    );
  }

  final String productId;
  final String? purchaseToken;
  final String? receipt;
}

/// Result of a failed purchase.
class PurchaseFailedResult {
  const PurchaseFailedResult({
    required this.error,
    this.productId,
    this.code,
  });

  final String error;
  final String? productId;
  final String? code;

  factory PurchaseFailedResult.fromMap(Map<Object?, Object?> map) {
    final m = Map<String, dynamic>.from(map as Map);
    return PurchaseFailedResult(
      error: m['error'] as String? ?? 'Unknown error',
      productId: m['productId'] as String?,
      code: m['code'] as String?,
    );
  }
}

/// Result of a restored purchase.
class PurchaseRestoredResult {
  const PurchaseRestoredResult({
    required this.productId,
    this.purchaseToken,
    this.receipt,
  });

  final String productId;
  final String? purchaseToken;
  final String? receipt;

  factory PurchaseRestoredResult.fromMap(Map<Object?, Object?> map) {
    final m = Map<String, dynamic>.from(map as Map);
    return PurchaseRestoredResult(
      productId: m['productId'] as String? ?? '',
      purchaseToken: m['purchaseToken'] as String?,
      receipt: m['receipt'] as String?,
    );
  }
}

/// Event emitted by the native side over the method channel.
sealed class NativeIapEvent {
  const NativeIapEvent();
}

final class NativeIapPurchaseComplete extends NativeIapEvent {
  const NativeIapPurchaseComplete(this.result);
  final PurchaseCompleteResult result;
}

final class NativeIapPurchaseFailed extends NativeIapEvent {
  const NativeIapPurchaseFailed(this.result);
  final PurchaseFailedResult result;
}

final class NativeIapPurchaseRestored extends NativeIapEvent {
  const NativeIapPurchaseRestored(this.result);
  final PurchaseRestoredResult result;
}

final class NativeIapPurchasePending extends NativeIapEvent {
  const NativeIapPurchasePending({required this.productId});
  final String productId;
}

final class NativeIapPurchaseAcknowledged extends NativeIapEvent {
  const NativeIapPurchaseAcknowledged({
    required this.productId,
    this.purchaseToken,
  });
  final String productId;
  final String? purchaseToken;
}

final class NativeIapPurchaseDeferred extends NativeIapEvent {
  const NativeIapPurchaseDeferred({required this.productId});
  final String productId;
}

final class NativeIapPurchaseInProgress extends NativeIapEvent {
  const NativeIapPurchaseInProgress({required this.productId});
  final String productId;
}
