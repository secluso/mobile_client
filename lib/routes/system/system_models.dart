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

/// The account's single plan, shared across all its cameras.
@immutable
class AccountPlanSummary {
  const AccountPlanSummary({
    required this.tier,
    required this.price,
    required this.renewal,
    required this.usedLabel,
    required this.limitLabel,
    required this.usedFraction,
    required this.viewersNote,
    required this.cameras,
  });

  final PlanTier tier;

  /// e.g. "$6/mo". Lives on the account, not the camera.
  final String price;

  /// e.g. "renews Jul 28".
  final String renewal;

  /// Used side of the storage meter, e.g. "320 GB".
  final String usedLabel;

  /// Total side of the meter, e.g. "1 TB".
  final String limitLabel;

  /// 0.0 to 1.0, how full the shared allowance is.
  final double usedFraction;

  /// e.g. "up to 6 viewers".
  final String viewersNote;

  /// The cameras drawing on this plan.
  final List<AccountCamera> cameras;
}

@immutable
class AccountCamera {
  const AccountCamera({required this.name, this.usage, this.shared = false});

  final String name;

  /// This camera's slice of the shared storage
  final String? usage;

  /// Someone else has been given access to this camera.
  final bool shared;
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
    required this.line,
    required this.people,
    this.meta,
    this.storedOnRelay,
    this.storedLimit,
    this.motionClips,
    this.livestream,
  });

  final String cameraName;
  final PlanTier tier;

  /// Mono line: quality/renewal context.
  final String? meta;

  /// One sentence on what the tier means for you.
  final String line;

  /// Per-camera usage.
  final String? storedOnRelay;
  final String? storedLimit;
  final String? motionClips;
  final String? livestream;

  bool get hasUsage => storedOnRelay != null;

  final List<SharedPerson> people;
}
