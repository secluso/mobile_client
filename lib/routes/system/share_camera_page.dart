//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Who can watch one camera.

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_models.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';

class ShareCameraPage extends StatelessWidget {
  const ShareCameraPage({
    required this.cameraName,
    required this.people,
    required this.onAddPerson,
    required this.onRemovePerson,
    super.key,
  });

  final String cameraName;
  final List<SharedPerson> people;
  final VoidCallback onAddPerson;
  final ValueChanged<SharedPerson> onRemovePerson;

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            DetailHeader(title: 'Share $cameraName', palette: palette),

            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Anyone you add can watch $cameraName live and see its clips. '
                'It never costs them anything, and it never touches your plan.',
                style: palette.subtitle,
              ),
            ),

            SectionHead(
              label: 'People',
              palette: palette,
              note: '${people.length}',
            ),

            for (final (index, person) in people.indexed)
              _PersonRow(
                person: person,
                palette: palette,
                seed: index,
                onRemove: person.isOwner ? null : () => onRemovePerson(person),
              ),

            InvitationRow(
              mark: ScanMark(palette: palette),
              eyebrow: 'Free for them',
              title: 'Add a person',
              palette: palette,
              onTap: onAddPerson,
            ),

            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                "Adding someone shares this camera's keys, sealed device to "
                'device.',
                textAlign: TextAlign.center,
                style: palette.eyebrow.copyWith(
                  fontSize: 11,
                  letterSpacing: 11 * 0.04,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.palette,
    required this.seed,
    required this.onRemove,
  });

  final SharedPerson person;
  final SystemPalette palette;
  final int seed;

  /// Null for the owner, who cannot be removed.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: PortraitMark(
              palette: palette,
              seed: seed,
              isYou: person.isOwner,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  overflow: TextOverflow.ellipsis,
                  style: palette.cameraName,
                ),
                const SizedBox(height: 3),
                Text(person.role, style: palette.cameraState),
              ],
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 12),
            _RemoveButton(
              palette: palette,
              onTap: onRemove!,
              name: person.name,
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({
    required this.palette,
    required this.onTap,
    required this.name,
  });

  final SystemPalette palette;
  final VoidCallback onTap;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: CircleBorder(side: BorderSide(color: palette.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: 'Remove $name',
          child: SizedBox.square(
            dimension: 30,
            child: Icon(
              Icons.close_rounded,
              size: 15,
              color: palette.dim(0.38),
            ),
          ),
        ),
      ),
    );
  }
}
