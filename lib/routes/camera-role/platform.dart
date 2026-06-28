//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Platform;

/// The camera role is Android-only. iOS phones are not cheap; doesn't make sense to prioritize support for them yet.
bool get cameraRoleSupported => Platform.isAndroid;
