import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'smartpark_ui.dart';
import 'sp_audit_format.dart';
import '../utils/staff_credentials.dart' show isStaffAuthEmail;

/// Groups of audit actions, for the filter chips and icons.
enum SpAuditCategory {
  facility('Facility', Icons.apartment_rounded),
  staff('Staff', Icons.badge_outlined),
  refund('Refunds', Icons.currency_exchange_rounded),
  report('Reports', Icons.flag_outlined),
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
    // Gate records the owner or a supervisor corrected after the scan.
    'facility' || 'privacy' || 'gate' => SpAuditCategory.facility,
    // Cash handed over by a staff member.
    'staff' || 'cash' => SpAuditCategory.staff,
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
  // A Cloud Function acting on someone's request signs as its service
  // account ("...@developer.gserviceaccount.com"): that is SmartPark itself.
  if (name.endsWith('gserviceaccount.com')) return 'SmartPark';
  // Older entries: a staff member or supervisor logged under their sign-in
  // email ("user@staff.smartpark.internal"): show the username instead.
  // An email with no role is a project member's console or script edit.
  final String who = name.isEmpty
      ? 'Unknown'
      : isStaffAuthEmail(name)
      ? name.split('@').first
      : (name.contains('@') && role.isEmpty)
      ? 'SmartPark team'
      : name;
  if (role.isEmpty) return who;
  return '$who (${role[0].toUpperCase()}${role.substring(1)})';
}

/// Entries that only repeat another one: a password reset is logged by
/// the reset itself ("Reset the password of ...") and again as an edit of
/// the staff record's passwordResetAt.
bool spAuditIsDuplicate(Map<String, dynamic> entry) {
  if (entry['action'] != 'staff.updated') return false;
  final Map<String, dynamic> changes =
      (entry['changes'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  return changes.isNotEmpty &&
      changes.keys.every((String k) => k == 'passwordResetAt');
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
              final List<Map<String, dynamic>> all = docs
                  .map(
                    (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data(),
                  )
                  .where((Map<String, dynamic> e) => !spAuditIsDuplicate(e))
                  .toList();
              final Map<SpAuditCategory, int> counts = <SpAuditCategory, int>{};
              for (final Map<String, dynamic> e in all) {
                final SpAuditCategory c = spAuditCategory(
                  (e['action'] as String?) ?? '',
                );
                counts[c] = (counts[c] ?? 0) + 1;
              }
              final List<Map<String, dynamic>> entries = all
                  .where(
                    (Map<String, dynamic> e) =>
                        _category == null ||
                        spAuditCategory((e['action'] as String?) ?? '') ==
                            _category,
                  )
                  .toList();
              final bool mayHaveMore = docs.length >= _limit;

              return Column(
                children: <Widget>[
                  _filters(all.length, counts),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: <Widget>[
                        if (entries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SpEmptyState(
                              icon: Icons.history_rounded,
                              message: _category == null
                                  ? 'Nothing has been recorded yet.'
                                  : 'No ${_category!.label.toLowerCase()} '
                                        'changes in the loaded history.',
                            ),
                          ),
                        for (int i = 0; i < entries.length; i++) ...<Widget>[
                          // A heading at the start of each day; the cards
                          // then only need the time.
                          if (_startsDay(entries, i))
                            _DayHeading(entries[i]['at']),
                          _AuditEntryTile(
                            entry: entries[i],
                            admin: widget.admin,
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (mayHaveMore)
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _limit += _pageSize),
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Load older entries'),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
      ),
    );
  }

  bool _startsDay(List<Map<String, dynamic>> entries, int i) {
    if (i == 0) return true;
    final DateTime? here = spParseDateTime(entries[i]['at'])?.toLocal();
    final DateTime? before = spParseDateTime(entries[i - 1]['at'])?.toLocal();
    if (here == null || before == null) return here != before;
    return !spSameDate(here, before);
  }

  /// One row of pills that scrolls sideways, pinned above the list, each
  /// with how many loaded entries it holds.
  Widget _filters(int total, Map<SpAuditCategory, int> counts) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            _FilterPill(
              label: 'All',
              count: total,
              selected: _category == null,
              onTap: () => setState(() => _category = null),
            ),
            for (final SpAuditCategory category in _categories)
              _FilterPill(
                label: category.label,
                icon: category.icon,
                count: counts[category] ?? 0,
                selected: _category == category,
                onTap: () => setState(
                  () => _category = _category == category ? null : category,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fore = selected ? AppTheme.surface : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppTheme.textDark : AppTheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppTheme.textDark : AppTheme.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: fore),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fore,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.surface.withValues(alpha: 0.2)
                        : AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: fore,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.rawAt);

  final Object? rawAt;

  @override
  Widget build(BuildContext context) {
    final DateTime? at = spParseDateTime(rawAt)?.toLocal();
    final DateTime now = DateTime.now();
    final String label = at == null
        ? 'Just now'
        : spSameDate(at, now)
        ? 'Today'
        : spSameDate(at, now.subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : spFormatDate(at);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  const _AuditEntryTile({required this.entry, required this.admin});

  final Map<String, dynamic> entry;

  /// Admins see every facility, so the facility is named, and whether its
  /// owner can also see the entry.
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final String action = (entry['action'] as String?) ?? '';
    final SpAuditCategory category = spAuditCategory(action);
    final bool severe = spAuditIsSevere(action);
    final DateTime? at = spParseDateTime(entry['at'])?.toLocal();
    final String facility = ((entry['establishmentName'] as String?) ?? '')
        .trim();
    final List<SpAuditLine> lines = <SpAuditLine>[
      ...spAuditLines(
        (entry['details'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        action: action,
        at: at,
      ),
      ...spAuditLines(
        (entry['changes'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        action: action,
        at: at,
      ),
    ];
    final Color tone = severe ? AppTheme.danger : AppTheme.textDark;
    final Color iconTone = severe ? AppTheme.danger : AppTheme.accentText;
    final Color iconBack = severe ? AppTheme.dangerSoft : AppTheme.accentSoft;

    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool mine =
        uid.isNotEmpty && ((entry['actorId'] as String?) ?? '') == uid;
    final String meta = <String>[
      mine ? 'You' : spAuditActorLabel(entry),
      if (admin && facility.isNotEmpty) facility,
      // Non-breaking, so "3:30 PM" never splits across lines.
      if (at != null) spFormatClockTime(at).replaceAll(' ', ' '),
    ].joinDots();

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBack,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(category.icon, size: 19, color: iconTone),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                spAuditSummaryText(action, (entry['summary'] as String?) ?? ''),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                meta,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
              if (admin && ((entry['ownerId'] as String?) ?? '').isNotEmpty)
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

    return Material(
      color: AppTheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        side: BorderSide(color: spCardBorder),
      ),
      child: lines.isEmpty
          ? Padding(padding: const EdgeInsets.all(14), child: header)
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                title: header,
                children: <Widget>[_DetailsPanel(lines)],
              ),
            ),
    );
  }
}

/// An entry's details: labels on the left, values on the right; a change
/// shows the old value faded and struck through, then the new one.
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel(this.lines);

  final List<SpAuditLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < lines.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 108,
                    child: Text(
                      lines[i].label,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _value(lines[i])),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _value(SpAuditLine line) {
    final TextStyle now = TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppTheme.textDark,
    );
    final TextStyle old = TextStyle(
      fontSize: 13,
      height: 1.35,
      color: AppTheme.textHint,
      decoration: TextDecoration.lineThrough,
      decorationColor: AppTheme.textHint,
    );
    if (line.cleared) {
      return Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: line.value, style: old),
            const TextSpan(text: '  '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Cleared',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (line.before == null) return Text(line.value, style: now);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: line.before, style: old),
          TextSpan(
            text: '  →  ',
            style: TextStyle(color: AppTheme.textMuted),
          ),
          TextSpan(text: line.value, style: now),
        ],
      ),
      style: const TextStyle(fontSize: 13, height: 1.35),
    );
  }
}
