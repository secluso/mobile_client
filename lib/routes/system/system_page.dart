//! SPDX-License-Identifier: GPL-3.0-or-later
//
// The System tab once a relay is connected
//   Secluso relay, several cameras   - account row, per-camera plans
//   Secluso relay, one camera        - plus a ghost slot, so the list still reads as a list
//   Secluso relay, no cameras        - the empty scene instead of the roster
//   Self-hosted relay                - no account, no plans, online status instead

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';

class SystemPage extends StatelessWidget {
  const SystemPage({
    required this.relay,
    required this.cameras,
    required this.onOpenRelay,
    required this.onAddCamera,
    required this.onOpenCamera,
    this.accountEmail,
    this.plan,
    this.onManageAccount,
    super.key,
  });

  final SystemRelay relay;
  final List<SystemCamera> cameras;

  /// Account the relay subscription belongs to. Null on a self-hosted relay,
  /// which has no account.
  final String? accountEmail;

  final CameraPlan? plan;

  final VoidCallback onOpenRelay;
  final VoidCallback onAddCamera;
  final ValueChanged<SystemCamera> onOpenCamera;
  final VoidCallback? onManageAccount;

  bool get _hasPlans => !relay.isSelfHosted;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Material(
      color: palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text('System', style: palette.title),
          const SizedBox(height: 2),
          Text('Your relay and cameras.', style: palette.subtitle),
          _RelayRow(
            relay: relay,
            palette: palette,
            onTap: onOpenRelay,
            // Self-hosted has no account row beneath
            ruled: _hasPlans,
          ),
          if (accountEmail != null && onManageAccount != null)
            _AccountRow(
              email: accountEmail!,
              palette: palette,
              onTap: onManageAccount!,
            ),
          // One plan for the account, shared across the cameras below.
          if (_hasPlans && plan != null && onManageAccount != null)
            _PlanSummaryRow(
              plan: plan!,
              palette: palette,
              onTap: onManageAccount!,
            ),
          ..._roster(palette),
        ],
      ),
    );
  }

  List<Widget> _roster(SystemPalette palette) {
    if (cameras.isEmpty) {
      return [
        _EmptyWatch(palette: palette),
        _LinkRow(
          label: 'Add your first camera',
          palette: palette,
          onTap: onAddCamera,
          ruledAbove: true,
        ),
      ];
    }

    return [
      _SectionHead(
        label: 'Cameras',
        palette: palette,
        // The managed relay offers a way to add; the self-hosted one just
        // reports how many are up.
        action: _hasPlans && cameras.length > 1 ? '+ Add' : null,
        onAction: onAddCamera,
        note:
            _hasPlans
                ? null
                : '${cameras.where((c) => c.online).length} online',
      ),
      for (final camera in cameras)
        _CameraRow(
          camera: camera,
          palette: palette,
          onTap: _hasPlans ? () => onOpenCamera(camera) : null,
        ),
      // A single camera would leave the list looking unfinished
      if (_hasPlans && cameras.length == 1)
        _GhostRow(palette: palette, onTap: onAddCamera),
      _EncryptionNote(palette: palette, selfHosted: relay.isSelfHosted),
    ];
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({
    required this.relay,
    required this.palette,
    required this.onTap,
    required this.ruled,
  });

  final SystemRelay relay;
  final SystemPalette palette;
  final VoidCallback onTap;
  final bool ruled;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 22),
        padding: EdgeInsets.only(bottom: ruled ? 20 : 6),
        decoration: BoxDecoration(
          border:
              ruled
                  ? Border(bottom: BorderSide(color: palette.hairline))
                  : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR RELAY', style: palette.eyebrow),
                  const SizedBox(height: 6),
                  Text(relay.name, style: palette.relayName),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      _Dot(
                        size: 7,
                        color:
                            relay.connected ? palette.success : palette.danger,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relay.connected ? 'Connected' : 'Not connected',
                        style: palette.relayStatus,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(relay.endpoint, style: palette.relayEndpoint),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 74,
              height: 60,
              child:
                  relay.isSelfHosted
                      ? SelfHostedMark(palette: palette)
                      : RelayGateMark(palette: palette),
            ),
            const SizedBox(width: 8),
            _Chevron(palette: palette, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.email,
    required this.palette,
    required this.onTap,
  });

  final String email;
  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACCOUNT', style: palette.eyebrow),
                  const SizedBox(height: 5),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: palette.accountEmail,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('Manage', style: palette.action),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.blue),
          ],
        ),
      ),
    );
  }
}

class _PlanSummaryRow extends StatelessWidget {
  const _PlanSummaryRow({
    required this.plan,
    required this.palette,
    required this.onTap,
  });

  final CameraPlan plan;
  final SystemPalette palette;
  final VoidCallback onTap;

  Color get _tierColor => switch (plan.tier) {
    PlanTier.free => palette.warmDim,
    PlanTier.premium => palette.blue,
    PlanTier.anonymous => palette.mint,
  };

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PLAN', style: palette.eyebrow),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: plan.tier.label,
                          style: TextStyle(color: _tierColor),
                        ),
                        TextSpan(text: '  ·  ${plan.usage}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.accountEmail,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('Manage', style: palette.action),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.blue),
          ],
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.label,
    required this.palette,
    this.action,
    this.onAction,
    this.note,
  });

  final String label;
  final SystemPalette palette;

  /// A blue call to action on the right, e.g. "+ Add".
  final String? action;
  final VoidCallback? onAction;

  /// A quiet counterpart on the right, e.g. "3 online".
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(), style: palette.sectionLabel),
          ),
          if (action != null)
            _Tappable(
              onTap: onAction,
              child: Text(action!, style: palette.action),
            )
          else if (note != null)
            Text(note!, style: palette.sectionNote),
        ],
      ),
    );
  }
}

class _CameraRow extends StatelessWidget {
  const _CameraRow({
    required this.camera,
    required this.palette,
    required this.onTap,
  });

  final SystemCamera camera;
  final SystemPalette palette;

  /// Null on a self-hosted relay, where the rows are a read-only roster.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final plan = camera.plan;
    return _Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            _Thumbnail(camera: camera, palette: palette),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          camera.name,
                          overflow: TextOverflow.ellipsis,
                          style: palette.cameraName,
                        ),
                      ),
                      if (camera.shared) ...[
                        const SizedBox(width: 7),
                        _Dot(size: 4, color: palette.dim(0.38)),
                        const SizedBox(width: 4),
                        Text('shared', style: palette.sharedTag),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (plan != null)
                    _PlanMeta(plan: plan, palette: palette)
                  else
                    Row(
                      children: [
                        _Dot(
                          size: 6,
                          color:
                              camera.online
                                  ? palette.success
                                  : palette.dim(0.38),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          camera.online ? 'Online' : 'Offline',
                          style: palette.cameraState,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 12),
              _Chevron(palette: palette, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// "PREMIUM · 320 GB OF 1 TB"
class _PlanMeta extends StatelessWidget {
  const _PlanMeta({required this.plan, required this.palette});

  final CameraPlan plan;
  final SystemPalette palette;

  Color get _tierColor => switch (plan.tier) {
    PlanTier.free => palette.warmDim,
    PlanTier.premium => palette.blue,
    PlanTier.anonymous => palette.mint,
  };

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: plan.tier.label.toUpperCase(),
            style: TextStyle(color: _tierColor),
          ),
          TextSpan(text: '  ·  ${plan.usage.toUpperCase()}'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: palette.cameraMeta,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.camera, required this.palette});

  static const _size = 44.0;

  final SystemCamera camera;
  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    final thumbnail = camera.thumbnail;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: _size,
        child:
            thumbnail == null
                ? ColoredBox(
                  color: palette.dim(0.06),
                  child: Icon(
                    Icons.videocam_outlined,
                    size: 20,
                    color: palette.dim(0.3),
                  ),
                )
                : Image(image: thumbnail, fit: BoxFit.cover),
      ),
    );
  }
}

/// The slot the next camera could fill.
class _GhostRow extends StatelessWidget {
  const _GhostRow({required this.palette, required this.onTap});

  final SystemPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: GhostSlotMark(palette: palette),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room for another camera',
                    style: palette.cameraName.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: palette.dim(0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // A sentence, not ledger data, so it stays out of mono caps.
                  Text(
                    'A spare Android phone is all it takes',
                    style: palette.emptyBody.copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      color: palette.dim(0.38),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Chevron(palette: palette, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyWatch extends StatelessWidget {
  const _EmptyWatch({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 30, 0, 4),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth * 0.72).clamp(0.0, 214.0);
              return SizedBox(
                width: width,
                height: width / EmptyWatchScene.aspect,
                child: EmptyWatchScene(palette: palette),
              );
            },
          ),
          const SizedBox(height: 4),
          Text('Nothing on watch yet.', style: palette.emptyTitle),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'Your relay is ready. Add a camera, or stand a spare Android '
              'phone on a shelf. About five minutes, start to finish.',
              textAlign: TextAlign.center,
              style: palette.emptyBody,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.palette,
    required this.onTap,
    this.ruledAbove = false,
  });

  final String label;
  final SystemPalette palette;
  final VoidCallback onTap;
  final bool ruledAbove;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(top: ruledAbove ? 28 : 0),
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          border: Border(
            top:
                ruledAbove
                    ? BorderSide(color: palette.hairline)
                    : BorderSide.none,
            bottom: BorderSide(color: palette.hairline),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: palette.linkRow)),
            _Chevron(palette: palette, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Replaced the boxed green card that used to sit here.
class _EncryptionNote extends StatelessWidget {
  const _EncryptionNote({required this.palette, required this.selfHosted});

  final SystemPalette palette;
  final bool selfHosted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.lock_rounded,
              size: 14,
              color: palette.success.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              selfHosted
                  ? "End-to-end encrypted. Your relay only ever carries sealed "
                      "traffic it can't read."
                  : 'End-to-end encrypted. Your keys and footage never leave '
                      'this phone.',
              style: palette.footnote,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.palette, required this.size});

  final SystemPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.chevron_right_rounded, size: size, color: palette.dim(0.38));
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Keeps rows flush to the page edges
class _Tappable extends StatefulWidget {
  const _Tappable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
