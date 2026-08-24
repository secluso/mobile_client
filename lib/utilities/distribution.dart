//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Where this build came from:
// - through the platform store (Google Play / App Store)
// - or, for builds without a store, on the web.

import 'dart:io' show Platform;

enum DistributionChannel { playStore, appStore, fdroid, direct }

class Distribution {
  Distribution._();

  /// Set at build time for the F-Droid artifact.
  static const bool _fdroidBuild = bool.fromEnvironment('SECLUSO_FDROID_BUILD');

  /// Explicit channel tag for builds that can't be inferred
  static const String _override = String.fromEnvironment(
    'SECLUSO_DISTRIBUTION',
  );

  /// Where users without in-app purchase go to subscribe or manage a plan.
  static const String billingPortalUrl = 'https://secluso.com/account';

  static DistributionChannel get channel {
    switch (_override) {
      case 'play':
        return DistributionChannel.playStore;
      case 'appstore':
        return DistributionChannel.appStore;
      case 'fdroid':
        return DistributionChannel.fdroid;
      case 'direct':
        return DistributionChannel.direct;
    }

    if (Platform.isIOS) return DistributionChannel.appStore;
    if (_fdroidBuild) return DistributionChannel.fdroid;
    return DistributionChannel.playStore;
  }

  static bool get supportsInAppPurchase =>
      channel == DistributionChannel.playStore ||
      channel == DistributionChannel.appStore;

  static String get storePlatform => Platform.isIOS ? 'apple' : 'google';
}
