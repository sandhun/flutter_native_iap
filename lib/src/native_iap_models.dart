
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
