import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Groups of audit actions, for the filter chips and icons.
enum SpAuditCategory {
  facility('Facilities', Icons.apartment_rounded),
  staff('Staff', Icons.badge_outlined),
  refund('Refunds', Icons.currency_exchange_rounded),
  report('Reports & warnings', Icons.flag_outlined),
  account('Accounts', Icons.person_outline_rounded),
  maintenance('Maintenance', Icons.build_circle_outlined),
  other('Other', Icons.history_rounded);

  const SpAuditCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The category of an audit [action] such as `facility.approved`.
SpAuditCategory spAuditCategory(String action) {
  final String prefix = action.split('.').first;
  return switch (prefix) {
    // A closed facility's documents deleted on schedule.
    'facility' || 'privacy' => SpAuditCategory.facility,
    'staff' => SpAuditCategory.staff,
    'refund' => SpAuditCategory.refund,
    'report' || 'driver' => SpAuditCategory.report,
    'account' => SpAuditCategory.account,
    'maintenance' => SpAuditCategory.maintenance,
    _ => SpAuditCategory.other,
  };
}

/// Actions that take something away from someone, shown in red.
bool spAuditIsSevere(String action) {
  return const <String>{
    'facility.rejected',
    'facility.suspended',
    'facility.deactivated',
    'facility.deleted',
    'staff.deactivated',
    'staff.removed',
    'driver.warned',
    'account.deleted',
  }.contains(action);
}

/// Who did it, as shown under an entry: "Juan Cruz (admin)".
String spAuditActorLabel(Map<String, dynamic> entry) {
  final String name = ((entry['actorName'] as String?) ?? '').trim();
  final String role = ((entry['actorRole'] as String?) ?? '').trim();
  final String who = name.isEmpty ? 'Unknown' : name;
  return role.isEmpty ? who : '$who ($role)';
}

/// Card that opens the audit log: every entry for admins ([admin] true),
/// or the entries about the signed-in owner's facility and staff.
class SpAuditLogCard extends StatelessWidget {
  const SpAuditLogCard({super.key, required this.admin});

  final bool admin;

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.manage_history_rounded,
      title: admin ? 'Audit Log' : 'Change History',
      subtitle: admin
          ? 'Who approved, suspended, refunded, warned or changed what, '
                'and when.'
          : 'Every change to your facility, rates and staff: who made it '
                'and when, including SmartPark\'s review decisions.',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SpAuditLogPage(admin: admin),
            ),
          ),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: Text(
            admin ? 'View audit log' : 'View change history',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ),
    );
  }
}

/// The audit log itself, newest first.
class SpAuditLogPage extends StatefulWidget {
  const SpAuditLogPage({super.key, required this.admin});

  final bool admin;

  @override
  State<SpAuditLogPage> createState() => _SpAuditLogPageState();
}

class _SpAuditLogPageState extends State<SpAuditLogPage> {
  static const int _pageSize = 50;

  int _limit = _pageSize;
  SpAuditCategory? _category;

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'audit_logs',
    );
    if (!widget.admin) {
      // The rules only let an owner read entries carrying their uid.
      query = query.where(
        'ownerId',
        isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
    }
    return query.orderBy('at', descending: true).limit(_limit);
  }

  List<SpAuditCategory> get _categories => widget.admin
      ? SpAuditCategory.values
            .where((SpAuditCategory c) => c != SpAuditCategory.other)
            .toList()
      : const <SpAuditCategory>[
          SpAuditCategory.facility,
          SpAuditCategory.staff,
          SpAuditCategory.refund,
          SpAuditCategory.report,
        ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(widget.admin ? 'Audit Log' : 'Change History'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query().snapshots(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
            ) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: SpEmptyState(
                    icon: Icons.error_outline_rounded,
                    message: 'Could not load the history. Please try again.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                  snapshot.data!.docs;
              final List<Map<String, dynamic>> entries = docs
                  .map(
                    (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data(),
                  )
                  .where(
                    (Map<String, dynamic> e) =>
                        _category == null ||
                        spAuditCategory((e['action'] as String?) ?? '') ==
                            _category,
                  )
                  .toList();
              final bool mayHaveMore = docs.length >= _limit;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: <Widget>[
                  _filters(),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    SpEmptyState(
                      icon: Icons.history_rounded,
                      message: _category == null
                          ? 'Nothing has been recorded yet.'
                          : 'No ${_category!.label.toLowerCase()} entries '
                                'in the loaded history.',
                    ),
                  for (final Map<String, dynamic> entry in entries) ...<Widget>[
                    _AuditEntryTile(
                      entry: entry,
                      showOwnerFacing: widget.admin,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (mayHaveMore)
                    TextButton.icon(
                      onPressed: () => setState(() => _limit += _pageSize),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Load older entries'),
                    ),
                ],
              );
            },
      ),
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: const Text('All'),
          selected: _category == null,
          onSelected: (_) => setState(() => _category = null),
        ),
        for (final SpAuditCategory category in _categories)
          ChoiceChip(
            avatar: Icon(category.icon, size: 16),
            label: Text(category.label),
            selected: _category == category,
            onSelected: (bool on) =>
                setState(() => _category = on ? category : null),
          ),
      ],
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  const _AuditEntryTile({required this.entry, required this.showOwnerFacing});

  final Map<String, dynamic> entry;

  /// Admins see whether the facility's owner can also see the entry.
  final bool showOwnerFacing;

  @override
  Widget build(BuildContext context) {
    final String action = (entry['action'] as String?) ?? '';
    final SpAuditCategory category = spAuditCategory(action);
    final bool severe = spAuditIsSevere(action);
    final DateTime? at = spParseDateTime(entry['at']);
    final String facility = ((entry['establishmentName'] as String?) ?? '')
        .trim();
    final Map<String, dynamic> changes =
        (entry['changes'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> details =
        (entry['details'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<MapEntry<String, dynamic>> notes = details.entries
        .where(
          (MapEntry<String, dynamic> e) =>
              e.value != null && e.value.toString().trim().isNotEmpty,
        )
        .toList();
    final Color tone = severe ? AppTheme.danger : AppTheme.textDark;

    final String meta = <String>[
      spAuditActorLabel(entry),
      if (facility.isNotEmpty) facility,
      if (at != null) '${spFormatDate(at)}, ${spFormatClockTime(at)}',
    ].join(' · ');

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(category.icon, size: 20, color: tone),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                (entry['summary'] as String?)?.trim().isNotEmpty == true
                    ? entry['summary'] as String
                    : action,
                style: TextStyle(fontWeight: FontWeight.w700, color: tone),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              if (showOwnerFacing &&
                  ((entry['ownerId'] as String?) ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Also visible to the facility owner',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final bool hasMore = changes.isNotEmpty || notes.isNotEmpty;
    return Material(
      color: AppTheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        side: BorderSide(color: spCardBorder),
      ),
      child: !hasMore
          ? Padding(padding: const EdgeInsets.all(14), child: header)
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                childrenPadding: const EdgeInsets.fromLTRB(44, 0, 14, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: header,
                children: <Widget>[
                  for (final MapEntry<String, dynamic> note in notes)
                    _line(note.key, note.value.toString()),
                  for (final MapEntry<String, dynamic> change
                      in changes.entries)
                    _line(change.key, _changeText(change.value)),
                ],
              ),
            ),
    );
  }

  static String _changeText(Object? value) {
    if (value is! Map) return '$value';
    String show(Object? v) => v == null || '$v'.isEmpty ? '(none)' : '$v';
    return '${show(value['from'])}  →  ${show(value['to'])}';
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12.5, height: 1.35),
      ),
    );
  }
}
