//! SPDX-License-Identifier: GPL-3.0-or-later
//
// Setting up the relay account, and the form

import 'package:flutter/material.dart';
import 'package:secluso_flutter/routes/system/system_marks.dart';
import 'package:secluso_flutter/routes/system/system_theme.dart';
import 'package:secluso_flutter/routes/system/system_widgets.dart';
import 'package:secluso_flutter/utilities/relay_environment.dart';

/// The intro: what a relay account is for..
class RelayAccountPage extends StatefulWidget {
  const RelayAccountPage({
    required this.onCreateAccount,
    required this.onSignIn,
    super.key,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  State<RelayAccountPage> createState() => _RelayAccountPageState();
}

class _RelayAccountPageState extends State<RelayAccountPage> {
  /// Hidden: long-press the eyebrow to switch between production and staging.
  Future<void> _showEnvironmentSheet(SystemPalette palette) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Server environment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RelayEnvironment.isStaging
                        ? 'Currently: Staging'
                        : 'Currently: Production',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Staging access code',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                if (RelayEnvironment.isStaging)
                  TextButton(
                    onPressed: () async {
                      await RelayEnvironment.setStaging(false);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (mounted) setState(() {});
                    },
                    child: const Text('Use production'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!RelayEnvironment.unlocks(controller.text.trim())) {
                      setDialogState(() => error = 'Wrong code');
                      return;
                    }
                    await RelayEnvironment.setStaging(true);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Use staging'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
          children: [
            GestureDetector(
              onLongPress: () => _showEnvironmentSheet(palette),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text('SECLUSO RELAY', style: palette.eyebrow),
                  if (RelayEnvironment.isStaging) ...[
                    const SizedBox(width: 8),
                    _StagingBadge(palette: palette),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('Set up your relay account', style: palette.title),
            const SizedBox(height: 14),
            Text(
              'The relay is the bridge that carries your encrypted video from '
              "your camera to this phone. Your account pays for that bridge and "
              "proves you're allowed to use it. That's all it does.",
              style: palette.subtitle,
            ),

            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: AspectRatio(
                    aspectRatio: RelayAccountScene.aspect,
                    child: RelayAccountScene(palette: palette),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),
            _Fact(
              palette: palette,
              icon: Icons.check_rounded,
              tint: palette.blue.withValues(alpha: 0.12),
              iconColor: palette.blue,
              title: 'Pays for the relay and unlocks it.',
              body: 'Your plan and billing live here.',
            ),
            const SizedBox(height: 14),
            _Fact(
              palette: palette,
              icon: Icons.lock_rounded,
              tint: palette.ink.withValues(alpha: 0.06),
              iconColor: palette.warmDim,
              title: 'Never sees your cameras or footage.',
              body: 'Keys and video stay on this phone, sealed end to end.',
            ),

            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Create account · starts free',
              palette: palette,
              onPressed: widget.onCreateAccount,
            ),
            const SizedBox(height: 16),
            QuietLink(
              label: 'I already have an account',
              palette: palette,
              onTap: widget.onSignIn,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown by the eyebrow when the app is pointed at staging
class _StagingBadge extends StatelessWidget {
  const _StagingBadge({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: palette.warmDim.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'STAGING',
        style: palette.eyebrow.copyWith(
          fontSize: 8.5,
          letterSpacing: 8.5 * 0.12,
          color: palette.warmDim,
        ),
      ),
    );
  }
}

/// One half of what the account does, stated as a heading and a plain line.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.palette,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final SystemPalette palette;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: palette.linkRow.copyWith(
                  fontSize: 14.5,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: palette.emptyBody.copyWith(fontSize: 14, height: 1.42),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The form. One screen serves both creating an account and signing back into
/// one, because the fields are identical and only the wording changes.
class RelaySignUpPage extends StatefulWidget {
  const RelaySignUpPage({
    required this.onSubmit,
    this.onSkip,
    this.initialMode = AuthMode.create,
    super.key,
  });

  /// Called with the entered credentials.
  final void Function(AuthMode mode, String email, String password) onSubmit;

  /// Optional escape hatch below the form
  final VoidCallback? onSkip;
  final AuthMode initialMode;

  @override
  State<RelaySignUpPage> createState() => _RelaySignUpPageState();
}

enum AuthMode { create, signIn }

class _RelaySignUpPageState extends State<RelaySignUpPage> {
  late AuthMode _mode = widget.initialMode;
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _creating => _mode == AuthMode.create;

  void _flip() =>
      setState(() => _mode = _creating ? AuthMode.signIn : AuthMode.create);

  @override
  Widget build(BuildContext context) {
    final palette = SystemPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
          children: [
            Text('SECLUSO RELAY', style: palette.eyebrow),
            const SizedBox(height: 6),
            Text(
              _creating ? 'Create your account' : 'Sign back in',
              style: palette.title,
            ),
            const SizedBox(height: 14),
            Text(
              _creating
                  ? 'Just an email and a password. This is only for the relay, '
                      'never your video.'
                  : 'The same email and password you set up the relay with. It '
                      'still only unlocks the relay.',
              style: palette.subtitle,
            ),

            const SizedBox(height: 22),
            _Field(
              label: 'Email',
              hint: 'you@example.com',
              controller: _email,
              palette: palette,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Password',
              hint: '••••••••••••',
              controller: _password,
              palette: palette,
              obscure: true,
            ),

            const SizedBox(height: 18),
            _LoginNote(palette: palette),

            const SizedBox(height: 18),
            PrimaryButton(
              label: _creating ? 'Create account' : 'Sign in',
              palette: palette,
              onPressed:
                  () => widget.onSubmit(_mode, _email.text, _password.text),
            ),
            if (widget.onSkip != null) ...[
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Not now',
                palette: palette,
                onPressed: widget.onSkip!,
              ),
            ],
            const SizedBox(height: 16),
            QuietLink(
              label:
                  _creating
                      ? 'Actually, I already have an account'
                      : 'Actually, I need to create one',
              palette: palette,
              onTap: _flip,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.palette,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final SystemPalette palette;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: palette.ink.withValues(alpha: 0.10)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: palette.eyebrow.copyWith(letterSpacing: 10 * 0.2),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          style: palette.subtitle.copyWith(color: palette.text),
          cursorColor: palette.blue,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: palette.subtitle.copyWith(
              color: palette.warmDim.withValues(alpha: 0.55),
            ),
            filled: true,
            fillColor: palette.dim(0.02),
            contentPadding: const EdgeInsets.all(16),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(
                color: palette.blue.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Repeats the promise where it matters most: right above the button that
/// creates the account.
class _LoginNote extends StatelessWidget {
  const _LoginNote({required this.palette});

  final SystemPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: palette.blue.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: palette.blue.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_rounded, size: 15, color: palette.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This login only unlocks the relay. It can never unlock your '
              'footage. Your encryption keys never leave this phone.',
              style: palette.emptyBody.copyWith(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
