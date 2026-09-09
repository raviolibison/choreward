import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// TODO(billing): replace with real RevenueCat API keys once the RevenueCat
// project and store listings exist. Get these from
// https://app.revenuecat.com -> Project Settings -> API Keys.
const _revenueCatAndroidApiKey = 'REVENUECAT_ANDROID_API_KEY_PLACEHOLDER';
const _revenueCatIosApiKey = 'REVENUECAT_IOS_API_KEY_PLACEHOLDER';

// The RevenueCat entitlement identifier that unlocks premium features.
// Create this entitlement in the RevenueCat dashboard and attach it to
// whatever product(s) you set up in App Store Connect / Play Console.
// Must match PREMIUM_ENTITLEMENT_ID in functions/index.js.
const premiumEntitlementId = 'premium';

// RevenueCat billing (StoreKit / Play Billing) only exists on iOS and
// Android — there's nothing to wire up on desktop/web.
bool get isBillingSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class BillingService {
  static bool _configured = false;

  // Ties RevenueCat's purchaser identity to a household rather than an
  // individual user, since `isPremium` is a household-level flag — anyone
  // in the household can buy premium and it unlocks for everyone in it.
  // Call this whenever the active household changes (see
  // resolveActiveHouseholdId / the household switcher in family_service.dart).
  static Future<void> configureForHousehold(String householdId) async {
    if (!isBillingSupported) return;

    if (!_configured) {
      await Purchases.setLogLevel(LogLevel.warn);
      final configuration = PurchasesConfiguration(
        Platform.isIOS ? _revenueCatIosApiKey : _revenueCatAndroidApiKey,
      )..appUserID = householdId;
      await Purchases.configure(configuration);
      _configured = true;
    } else {
      await Purchases.logIn(householdId);
    }
  }

  static Future<Offerings?> getOfferings() async {
    if (!isBillingSupported) return null;
    return Purchases.getOfferings();
  }

  // Returns true if the purchase completed, false if the user cancelled.
  // Rethrows on any other failure.
  //
  // Note: this does NOT flip `isPremium` itself. Never trust a client's view
  // of entitlements for a security-relevant flag — the same reasoning that
  // moved household-join validation server-side (see joinHousehold in
  // functions/index.js and firestore.rules) applies here. The
  // `revenueCatWebhook` Cloud Function is the only thing that writes
  // `isPremium`, once RevenueCat confirms the purchase server-side.
  static Future<bool> purchasePackage(Package package) async {
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }
}
