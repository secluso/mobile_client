//! SPDX-License-Identifier: GPL-3.0-or-later
//
// In-app subscription purchases through Google Play and the App Store.
//
// F-Droid never goes here (see Distribution.supportsInAppPurchase)

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:secluso_flutter/utilities/distribution.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';

/// Subscription SKU
const String kPremiumProductId = 'secluso.premium.monthly';

class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService instance = BillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _initialised = false;
  bool _available = false;
  bool _purchasePending = false;
  bool _entitlementActive = false;
  String? _lastError;
  ProductDetails? _premium;

  /// Whether a store is reachable & this distro is allowed to sell
  bool get available => _available;

  bool get purchasePending => _purchasePending;

  bool get entitlementActive => _entitlementActive;

  /// The last purchase error, cleared when a new purchase starts.
  String? get lastError => _lastError;

  /// The premium product, once queried, for showing the store's localised price.
  ProductDetails? get premiumProduct => _premium;

  /// Wire up the purchase stream. Safe to call more than once. A no-op on builds
  /// without in-app purchase, so the plugin (and its Play Billing dependency) is
  /// never touched there.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    if (!Distribution.supportsInAppPurchase) {
      _available = false;
      return;
    }

    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      Log.d('Billing: store availability check failed: $e');
      _available = false;
    }
    if (!_available) {
      notifyListeners();
      return;
    }

    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => Log.d('Billing: purchase stream error: $e'),
    );

    unawaited(_loadProduct());
    notifyListeners();
  }

  Future<void> _loadProduct() async {
    try {
      final response = await _iap.queryProductDetails({kPremiumProductId});
      if (response.error != null) {
        Log.d('Billing: product query error: ${response.error}');
        return;
      }
      if (response.productDetails.isEmpty) {
        Log.d('Billing: product $kPremiumProductId not found in the store');
        return;
      }
      _premium = response.productDetails.first;
      notifyListeners();
    } catch (e) {
      Log.d('Billing: product query threw: $e');
    }
  }

  /// Start the store purchase flow for the premium plan.
  /// Results arrive asynchronously through the purchase stream.
  Future<bool> buyPremium() async {
    if (!_available) return false;

    _lastError = null;
    final product = _premium ?? await _queryPremiumOnce();
    if (product == null) {
      _lastError = 'This plan is not available on the store right now.';
      notifyListeners();
      return false;
    }

    _purchasePending = true;
    notifyListeners();

    try {
      // Auto-renewing subscriptions are non-consumable in the plugin's model.
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        _purchasePending = false;
        _lastError = 'The store declined to start the purchase.';
        notifyListeners();
      }
      return started;
    } catch (e) {
      _purchasePending = false;
      _lastError = 'Could not open the store: $e';
      notifyListeners();
      return false;
    }
  }

  Future<ProductDetails?> _queryPremiumOnce() async {
    try {
      final response = await _iap.queryProductDetails({kPremiumProductId});
      if (response.productDetails.isNotEmpty) {
        _premium = response.productDetails.first;
        return _premium;
      }
    } catch (e) {
      Log.d('Billing: on-demand product query threw: $e');
    }
    return null;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _purchasePending = true;
          notifyListeners();
          break;
        case PurchaseStatus.error:
          _purchasePending = false;
          _lastError = purchase.error?.message ?? 'The purchase failed.';
          notifyListeners();
          await _finalise(purchase);
          break;
        case PurchaseStatus.canceled:
          _purchasePending = false;
          notifyListeners();
          await _finalise(purchase);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyThenFinalise(purchase);
          break;
      }
    }
  }

  Future<void> _verifyThenFinalise(PurchaseDetails purchase) async {
    try {
      final result = await HttpClientService.instance.verifyPurchase(
        platform: Distribution.storePlatform,
        // Android: the plugin's serverVerificationData
        purchaseToken:
            Platform.isAndroid
                ? purchase.verificationData.serverVerificationData
                : null,
        // iOS: the StoreKit transaction identifier
        transactionId: Platform.isIOS ? purchase.purchaseID : null,
        environment:
            Platform.isIOS ? (kReleaseMode ? 'Production' : 'Sandbox') : null,
      );

      if (result.isSuccess) {
        final value = result.value!;
        _entitlementActive = value.active;
        _lastError = null;
        Log.d('Billing: verified ${value.tier} (${value.status})');
      } else {
        _lastError = 'We could not confirm the purchase: ${result.error}';
        Log.d('Billing: verify failed: ${result.error}');
      }
    } catch (e) {
      _lastError = 'We could not confirm the purchase: $e';
      Log.d('Billing: verify threw: $e');
    } finally {
      _purchasePending = false;
      notifyListeners();
      // Finalise regardless: an unverified purchase left pending would be refunded by the store.
      await _finalise(purchase);
    }
  }

  Future<void> _finalise(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        Log.d('Billing: completePurchase threw: $e');
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
