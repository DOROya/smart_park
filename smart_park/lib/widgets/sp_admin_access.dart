import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_access.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';
import 'sp_dialog.dart';

/// Colour of an access level's chip.
Color accessLevelColor(AccessLevel level) => switch (level) {
  AccessLevel.superAdmin => spDeniedColor,
  AccessLevel.admin => spInsideColor,
  AccessLevel.owner => spEntryColor,
  AccessLevel.supervisor || AccessLevel.staff => AppTheme.textSecondary,
  _ => spExitColor,
};

/// A user's access level, admin history and, for a super admin looking at
/// someone else, the buttons that change it. Normal admins see the same
/// facts and no buttons.
class SpAdminAccessPanel extends StatefulWidget {
  const SpAdminAccessPanel({
    super.key,
    required this.uid,
    required this.user,
    required this.callerLevel,
    required this.superAdminCount,
    this.promotedByName = '',
    this.service,
  });

  final String uid;
  final Map<String, dynamic> user;
  final AccessLevel callerLevel;

  /// How many super admins there are, so the last one can't be demoted.
  final int superAdminCount;
  final String promotedByName;
  final AdminAccessService? service;

  @override
  State<SpAdminAccessPanel> createState() => _SpAdminAccessPanelState();
}

class _SpAdminAccessPanelState extends State<SpAdminAccessPanel> {
  late final AdminAccessService _service =
      widget.service ?? AdminAccessService();
  bool _busy = false;

  bool get _isMe => FirebaseAuth.instance.currentUser?.uid == widget.uid;

  bool get _isFounder => widget.uid == kFoundingSuperAdminUid;

  Future<void> _run(
    String done,
    Future<void> Function() change, {
    required String password,
  }) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _service.reauthenticate(password);
      await change();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (navigator.canPop()) navigator.pop();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not change admin access.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promote() async {
    final ({bool superAdmin, String password})? choice =
        await showDialog<({bool superAdmin, String password})>(
          context: context,
          builder: (_) => _PromoteDialog(uid: widget.uid, service: _service),
        );
    if (choice == null) return;
    await _run(
      choice.superAdmin ? 'Made a super admin.' : 'Made an admin.',
      () => _service.promote(widget.uid, superAdmin: choice.superAdmin),
      password: choice.password,
    );
  }

  Future<void> _confirm({
    required String title,
    required String body,
    required String action,
    required String done,
    required Future<void> Function() change,
  }) async {
    final String? password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(title: title, body: body, action: action),
    );
    if (password == null) return;
    await _run(done, change, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final AccessLevel level = accessLevelOf(widget.user);
    final DateTime? since = spParseDateTime(widget.user['adminSince']);
    final String former = ((widget.user['formerRole'] as String?) ?? '').trim();
    final bool canChange =
        widget.callerLevel == AccessLevel.superAdmin && !_isMe;
    final TextStyle muted = TextStyle(fontSize: 12, color: AppTheme.textMuted);

    final List<Widget> actions = <Widget>[
      if (level == AccessLevel.driver)
        FilledButton.icon(
          onPressed: _busy ? null : _promote,
          icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
          label: const Text('Make admin'),
        ),
      if (level == AccessLevel.admin) ...<Widget>[
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Make super admin?',
                  body:
                      'A super admin can give and take admin access, '
                      'including yours.',
                  action: 'Make super admin',
                  done: 'Now a super admin.',
                  change: () => _service.setLevel(widget.uid, superAdmin: true),
                ),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('Make super admin'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Remove admin access?',
                  body:
                      'The account goes back to being a '
                      '${former.isEmpty || former == 'admin' ? 'Driver' : former} '
                      'account at once. Its tickets and temporary QRs work '
                      'again.',
                  action: 'Remove access',
                  done: 'Admin access removed.',
                  change: () => _service.remove(widget.uid),
                ),
          style: OutlinedButton.styleFrom(foregroundColor: spDeniedColor),
          icon: const Icon(Icons.remove_moderator_outlined, size: 18),
          label: const Text('Remove admin access'),
        ),
      ],
      // The last super admin keeps their level, and so does the first.
      if (level == AccessLevel.superAdmin &&
          widget.superAdminCount > 1 &&
          !_isFounder)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Make a normal admin?',
                  body:
                      'They keep admin access but can no longer change '
                      'anyone\'s access.',
                  action: 'Make normal admin',
                  done: 'Now a normal admin.',
                  change: () =>
                      _service.setLevel(widget.uid, superAdmin: false),
                ),
          icon: const Icon(Icons.shield_moon_outlined, size: 18),
          label: const Text('Make normal admin'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Access', style: muted),
            const SizedBox(width: 8),
            SpChip(
              label: accessLevelLabel(level),
              color: accessLevelColor(level),
            ),
          ],
        ),
        if (isAdminLevel(level)) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            <String>[
              if (since != null) 'Admin since ${spFormatDate(since)}',
              if (widget.promotedByName.isNotEmpty)
                'promoted by ${widget.promotedByName}',
              if (former.isNotEmpty && former != 'admin') 'was a $former',
            ].joinDots(),
            style: muted,
          ),
        ],
        if (_isFounder && canChange) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'First super admin: their access can\'t be changed.',
            style: muted,
          ),
        ] else if (canChange && actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ] else if (!canChange &&
            widget.callerLevel == AccessLevel.admin &&
            (level == AccessLevel.driver || isAdminLevel(level))) ...<Widget>[
          const SizedBox(height: 6),
          Text('Only a super admin can change admin access.', style: muted),
        ],
      ],
    );
  }
}

/// Password re-entry for one access change.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      icon: const SpDialogIcon(
        Icons.lock_outline_rounded,
        tone: SpDialogTone.info,
      ),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.body),
          const SizedBox(height: 14),
          _PasswordField(controller: _password),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _password,
          builder: (BuildContext context, _) => FilledButton(
            onPressed: _password.text.isEmpty
                ? null
                : () => Navigator.of(context).pop(_password.text),
            child: Text(widget.action),
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: true,
    autofocus: true,
    decoration: const InputDecoration(
      labelText: 'Your password',
      helperText: 'Needed for every access change.',
    ),
  );
}

/// Shows the candidate check, then asks for the level and the password.
class _PromoteDialog extends StatefulWidget {
  const _PromoteDialog({required this.uid, required this.service});

  final String uid;
  final AdminAccessService service;

  @override
  State<_PromoteDialog> createState() => _PromoteDialogState();
}

class _PromoteDialogState extends State<_PromoteDialog> {
  late final Future<AdminCandidate> _candidate = widget.service.candidate(
    widget.uid,
  );
  final TextEditingController _password = TextEditingController();
  bool _super = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Widget _check(bool ok, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 16,
          color: ok ? spEntryColor : spInsideColor,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminCandidate>(
      future: _candidate,
      builder: (BuildContext context, AsyncSnapshot<AdminCandidate> snap) {
        final AdminCandidate? c = snap.data;
        return AlertDialog(
          icon: const SpDialogIcon(
            Icons.admin_panel_settings_outlined,
            tone: SpDialogTone.warning,
          ),
          title: const Text('Make admin?'),
          content: SingleChildScrollView(
            child: snap.hasError
                ? Text(
                    friendlyError(
                      snap.error!,
                      fallback: 'Could not check this account.',
                    ),
                  )
                : c == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _check(
                        c.role == 'Driver',
                        c.role == 'Driver'
                            ? 'Driver account'
                            : 'Only driver accounts can be made admins '
                                  '(this is ${c.role.isEmpty ? 'unknown' : c.role}).',
                      ),
                      _check(
                        c.emailVerified,
                        c.emailVerified
                            ? 'Email verified'
                            : 'Email not verified yet',
                      ),
                      _check(
                        c.activeTickets == 0 && c.unusedPasses == 0,
                        c.activeTickets == 0 && c.unusedPasses == 0
                            ? 'No active tickets or temporary QRs'
                            : '${c.activeTickets} active ticket(s) and '
                                  '${c.unusedPasses} unused temporary QR(s). '
                                  'They stay valid but can\'t be used while '
                                  'the account is an admin.',
                      ),
                      if (c.canPromote) ...<Widget>[
                        const SizedBox(height: 10),
                        RadioGroup<bool>(
                          groupValue: _super,
                          onChanged: (bool? v) =>
                              setState(() => _super = v ?? false),
                          child: const Column(
                            children: <Widget>[
                              RadioListTile<bool>(
                                value: false,
                                contentPadding: EdgeInsets.zero,
                                title: Text('Admin'),
                                subtitle: Text('Everything except access'),
                              ),
                              RadioListTile<bool>(
                                value: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('Super admin'),
                                subtitle: Text('Can also change access'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PasswordField(controller: _password),
                      ],
                    ],
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (c?.canPromote ?? false)
              ListenableBuilder(
                listenable: _password,
                builder: (BuildContext context, _) => FilledButton(
                  onPressed: _password.text.isEmpty
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop((superAdmin: _super, password: _password.text)),
                  child: const Text('Make admin'),
                ),
              ),
          ],
        );
      },
    );
  }
}
