//! SPDX-License-Identifier: GPL-3.0-or-later
//
// What the System tab needs to know.

import 'package:flutter/widgets.dart';

enum RelayKind {
  /// The relay Secluso runs. Has an account and per-camera plans.
  secluso,

  /// A relay the user runs. No account, no plans, just cameras.
  selfHosted,
}

@immutable
class SystemRelay {
  const SystemRelay({
    required this.kind,
    required this.endpoint,
    this.connected = true,
  });

  final RelayKind kind;

  /// Host the app talks to, e.g. "relay.local:8443".
  final String endpoint;

  final bool connected;

  String get name =>
      kind == RelayKind.secluso ? 'Secluso Relay' : 'Self-Hosted';

  bool get isSelfHosted => kind == RelayKind.selfHosted;
}

enum PlanTier {
  free('Free'),
  premium('Premium'),
  anonymous('Anonymous');

  const PlanTier(this.label);

  final String label;
}

@immutable
class CameraPlan {
  const CameraPlan({required this.tier, required this.usage});

  final PlanTier tier;

  /// Preformatted, e.g. "320 GB of 1 TB".
  final String usage;
}

@immutable
class SystemCamera {
  const SystemCamera({
    required this.name,
    this.thumbnail,
    this.online = true,
    this.shared = false,
    this.plan,
  });

  final String name;

  /// Latest frame for this camera, when one has been downloaded.
  final ImageProvider? thumbnail;

  final bool online;

  /// Someone else has been given access to this camera.
  final bool shared;

  /// Only ever set on the Secluso relay, which is the one that has plans.
  final CameraPlan? plan;
}

/// One tier as offered on the plan chooser.
@immutable
class PlanOffer {
  const PlanOffer({
    required this.tier,
    required this.cost,
    required this.period,
    required this.allowance,
    this.note,
    this.popular = false,
  });

  final PlanTier tier;

  /// Headline price, e.g. "$6".
  final String cost;

  /// Suffix after the price, e.g. "/mo". Empty for a free plan.
  final String period;

  /// Mono line of what you get, e.g. "1 TB motion · 1 TB live · up to 2K".
  final String allowance;

  /// Plainer second line. The Anonymous tier explains itself differently, so it
  /// leaves this off.
  final String? note;

  final bool popular;
}

/// A plan as it appears on the account
@immutable
class AccountPlan {
  const AccountPlan({
    required this.tier,
    required this.price,
    required this.renewal,
    this.cameraName,
    this.shared = false,
  });

  final PlanTier tier;

  /// e.g. "$6/mo".
  final String price;

  /// e.g. "renews Jul 28", or what stands in for it on an unattached plan.
  final String renewal;

  /// Null when the plan is not on a camera yet.
  final String? cameraName;

  final bool shared;

  bool get isOpenSlot => cameraName == null;
}

/// Someone a camera has been shared with.
@immutable
class SharedPerson {
  const SharedPerson({
    required this.name,
    required this.role,
    this.isOwner = false,
  });

  final String name;

  /// What they can do, e.g. "Can watch live and see clips".
  final String role;

  /// The owner cannot be removed.
  final bool isOwner;
}

/// Everything the per-camera plan screen shows.
@immutable
class CameraPlanDetail {
  const CameraPlanDetail({
    required this.cameraName,
    required this.tier,
    required this.meta,
    required this.line,
    required this.storedOnRelay,
    required this.storedLimit,
    required this.motionClips,
    required this.livestream,
    required this.people,
  });

  final String cameraName;
  final PlanTier tier;

  /// Mono line: price, quality, renewal.
  final String meta;

  /// One sentence on what the tier means for you.
  final String line;

  final String storedOnRelay;
  final String storedLimit;
  final String motionClips;
  final String livestream;

  final List<SharedPerson> people;
}
