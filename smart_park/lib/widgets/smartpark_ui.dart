import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/parking_pricing.dart';
import '../theme/app_theme.dart';
import '../utils/staff_credentials.dart';

/// Shared dashboard building blocks so the staff and parking-owner screens
/// look the same: hero banner, stat tiles, section cards, the parking-slot
/// card and gate-scan cards.

Color get spCardBorder => AppTheme.border;
Color get spEntryColor => AppTheme.success;
Color get spExitColor => AppTheme.info;
Color get spInsideColor => AppTheme.accentText;
Color get spDeniedColor => AppTheme.danger;

/// Hours covered by a facility's base rate ("Base Package"). Gate exit scans
/// bill anything beyond this as overtime.
const int spBaseStayHours = kBaseStayHours;

/// e.g. "2 hrs", used next to base-rate prices.
const String spBaseStayLabel = '$spBaseStayHours hrs';

DateTime? spParseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

bool spSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String spFormatDate(DateTime date) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String spFormatClockTime(DateTime time) {
  final int hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final String minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

String spFormatDuration(Duration elapsed) {
  final int hours = elapsed.inHours;
  final int minutes = elapsed.inMinutes.remainder(60);
  return hours <= 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

String spGreeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 18
    ? 'Good afternoon'
    : 'Good evening';

String spLogScanType(Map<String, dynamic> data) =>
    ((data['scanType'] as String?) ?? 'entry').toLowerCase();

bool spIsAllowedLog(Map<String, dynamic> data) =>
    ((data['status'] as String?) ?? (data['decision'] as String?) ?? '')
        .toUpperCase() ==
    'ALLOWED';

/// Whether an allowed entry scan still has no matching exit.
bool spIsInsideLog(Map<String, dynamic> data) =>
    spIsAllowedLog(data) &&
    spLogScanType(data) == 'entry' &&
    ((data['isActive'] as bool?) ?? false);

/// Who recorded a gate log. Prefers the live name in [staffNames] (staff uid
/// to name), then the name stamped on the log, then the staff username.
String? spLogStaffName(
  Map<String, dynamic> data, [
  Map<String, String>? staffNames,
]) {
  final String staffId = ((data['staffId'] as String?) ?? '').trim();
  final String live = (staffNames?[staffId] ?? '').trim();
  if (live.isNotEmpty) return live;
  final String stamped = ((data['staffName'] as String?) ?? '').trim();
  if (stamped.isNotEmpty) return stamped;
  final String email = ((data['staffEmail'] as String?) ?? '').trim();
  if (email.isEmpty) return null;
  // Staff sign in as "<username>@<internal domain>"; show the username.
  return isStaffAuthEmail(email) ? email.split('@').first : email;
}

/// Cache key part for [day], e.g. "2026-9-26".
String spDayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

/// A facility's gate logs for one local day, newest first. Screens query a
/// single day so they don't download the facility's whole scan history.
Query<Map<String, dynamic>> spDayLogsQuery(String facilityId, DateTime day) {
  final DateTime start = DateTime(day.year, day.month, day.day);
  final DateTime end = DateTime(day.year, day.month, day.day + 1);
  return FirebaseFirestore.instance
      .collection('activity_logs')
      .where('establishmentID', isEqualTo: facilityId)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('timestamp', isLessThan: Timestamp.fromDate(end))
      .orderBy('timestamp', descending: true);
}

/// Entry logs still open (vehicle not yet exited), whatever day they began.
Query<Map<String, dynamic>> spInsideLogsQuery(String facilityId) {
  return FirebaseFirestore.instance
      .collection('activity_logs')
      .where('establishmentID', isEqualTo: facilityId)
      .where('isActive', isEqualTo: true);
}

List<Map<String, dynamic>> spDocsData(
  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
) => <Map<String, dynamic>>[
  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
      in snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
    doc.data(),
];

/// Gate-scan counts for one day, plus vehicles currently inside.
class SpActivitySummary {
  /// When [logs] only covers [day], pass the open entry logs as [insideLogs]
  /// so vehicles that came in on an earlier day still count as inside.
  SpActivitySummary.fromLogs(
    Iterable<Map<String, dynamic>> logs,
    DateTime day, {
    Iterable<Map<String, dynamic>>? insideLogs,
  }) {
    insideNow = (insideLogs ?? logs).where(spIsInsideLog).length;
    for (final Map<String, dynamic> data in logs) {
      // Pending server timestamps read as null; treat them as now.
      final DateTime timestamp =
          spParseDateTime(data['timestamp']) ?? DateTime.now();
      if (!spSameDate(timestamp, day)) {
        continue;
      }
      dayLogs.add(data);
      if (!spIsAllowedLog(data)) {
        denied++;
      } else if (spLogScanType(data) == 'entry') {
        entries++;
      } else {
        exits++;
      }
    }
    dayLogs.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final DateTime now = DateTime.now();
      return (spParseDateTime(b['timestamp']) ?? now).compareTo(
        spParseDateTime(a['timestamp']) ?? now,
      );
    });
  }

  int entries = 0;
  int exits = 0;
  int denied = 0;
  int insideNow = 0;
  final List<Map<String, dynamic>> dayLogs = <Map<String, dynamic>>[];
}

/// Whether the device is tablet-sized. Uses the shortest side so a phone
/// rotated to landscape still gets the phone layout.
bool spIsTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

/// Tablet side navigation replacing a phone's bottom bar. Collapsed it is a
/// compact icon rail; [extended] shows labels beside the icons. Each item is
/// (icon, selected icon, label).
class SpNavRail extends StatelessWidget {
  const SpNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.extended = false,
  });

  final List<(IconData, IconData, String)> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      extended: extended,
      minExtendedWidth: 208,
      backgroundColor: AppTheme.surface,
      indicatorColor: AppTheme.accent.withValues(alpha: 0.3),
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      groupAlignment: -0.9,
      selectedIconTheme: IconThemeData(color: AppTheme.textDark),
      unselectedIconTheme: IconThemeData(color: AppTheme.textMuted),
      selectedLabelTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textDark,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppTheme.textMuted,
      ),
      destinations: [
        for (final (IconData icon, IconData activeIcon, String label) in items)
          NavigationRailDestination(
            icon: Icon(icon),
            selectedIcon: Icon(activeIcon),
            label: Text(label),
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
      ],
    );
  }
}

/// Tablet body: [rail] on the left, [child] centered with a capped width so
/// cards don't stretch across the whole screen.
class SpRailLayout extends StatelessWidget {
  const SpRailLayout({super.key, required this.rail, required this.child});

  final Widget rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        rail,
        VerticalDivider(width: 1, thickness: 1, color: spCardBorder),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// App bar hamburger that toggles an [SpNavRail] between compact and
/// extended.
class SpMenuToggleButton extends StatelessWidget {
  const SpMenuToggleButton({
    super.key,
    required this.extended,
    required this.onPressed,
  });

  final bool extended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: extended ? 'Collapse menu' : 'Expand menu',
      icon: Icon(Icons.menu_rounded, color: AppTheme.textSecondary),
    );
  }
}

/// Circular app bar shortcut to the account tab. Ringed when [active].
class SpAccountAvatarButton extends StatelessWidget {
  const SpAccountAvatarButton({
    super.key,
    required this.child,
    required this.active,
    required this.onTap,
    this.tooltip = 'Profile',
  });

  final Widget child;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.3),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
              child: IconTheme.merge(
                data: IconThemeData(size: 18, color: AppTheme.textDark),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays [children] out in rows of [columns], each cell taking equal width.
/// Cells keep their natural height; a short last row is padded with blanks.
class SpGrid extends StatelessWidget {
  const SpGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = 12,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int start = 0; start < children.length; start += columns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = start; i < start + columns; i++) ...[
                if (i > start) SizedBox(width: spacing),
                Expanded(
                  child: i < children.length
                      ? children[i]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Page title with an optional subtitle and trailing widget.
class SpPageHeader extends StatelessWidget {
  const SpPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Yellow gradient banner used at the top of each dashboard.
class SpHeroBanner extends StatelessWidget {
  const SpHeroBanner({
    super.key,
    required this.title,
    this.badge,
    this.details = const <(IconData, String)>[],
    this.action,
  });

  final String title;
  final String? badge;
  final List<(IconData, String)> details;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.accentLight, AppTheme.accentWarm],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (badge != null && badge!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          for (final (IconData icon, String text) in details) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Dark full-width button used inside [SpHeroBanner].
class SpHeroButton extends StatelessWidget {
  const SpHeroButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.textDark,
          foregroundColor: AppTheme.onInk,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Accent-colored primary button used in section cards.
class SpPrimaryButton extends StatelessWidget {
  const SpPrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.onAccent,
          elevation: 0,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Bold section label shown above a group of cards.
class SpSectionLabel extends StatelessWidget {
  const SpSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// White card with an icon + title header.
class SpSectionCard extends StatelessWidget {
  const SpSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.expandChild = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  /// Stretches [child] over the space left under the header. Only for cards
  /// given a bounded height, e.g. a scrollable list sized by a sibling.
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.textDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

/// Small rounded status label.
class SpChip extends StatelessWidget {
  const SpChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Metric tile: colored icon, big value, label and caption.
class SpStatTile extends StatelessWidget {
  const SpStatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// Two [SpStatTile]s side by side.
class SpStatRow extends StatelessWidget {
  const SpStatRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

/// The four daily gate metrics shown on both dashboards.
class SpDailyActivityTiles extends StatelessWidget {
  const SpDailyActivityTiles({
    super.key,
    required this.summary,
    this.today = true,
    this.singleRow = false,
  });

  final SpActivitySummary summary;

  /// Whether [summary] is for today; otherwise captions say "that day".
  final bool today;

  /// Show all four tiles in one row (wide layouts) instead of a 2x2 grid.
  final bool singleRow;

  @override
  Widget build(BuildContext context) {
    final Widget entries = SpStatTile(
      icon: Icons.login_rounded,
      color: spEntryColor,
      label: today ? 'Daily Entries' : 'Entries',
      caption: today ? 'Allowed in today' : 'Allowed in that day',
      value: '${summary.entries}',
    );
    final Widget exits = SpStatTile(
      icon: Icons.logout_rounded,
      color: spExitColor,
      label: today ? 'Daily Exits' : 'Exits',
      caption: today ? 'Released today' : 'Released that day',
      value: '${summary.exits}',
    );
    final Widget inside = SpStatTile(
      icon: Icons.directions_car_filled_rounded,
      color: spInsideColor,
      label: 'Inside Now',
      caption: 'Vehicles parked',
      value: '${summary.insideNow}',
    );
    final Widget denied = SpStatTile(
      icon: Icons.block_rounded,
      color: spDeniedColor,
      label: 'Denied Scans',
      caption: today ? 'Rejected today' : 'Rejected that day',
      value: '${summary.denied}',
    );

    if (singleRow) {
      return SpGrid(
        columns: 4,
        spacing: 10,
        children: <Widget>[entries, exits, inside, denied],
      );
    }
    return Column(
      children: [
        SpStatRow(left: entries, right: exits),
        const SizedBox(height: 10),
        SpStatRow(left: inside, right: denied),
      ],
    );
  }
}

/// Icon + message placeholder for empty lists.
class SpEmptyState extends StatelessWidget {
  const SpEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.receipt_long_rounded,
    this.boxed = true,
  });

  final String message;
  final IconData icon;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final Widget content = Row(
      children: [
        Icon(icon, color: AppTheme.borderStrong),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(color: AppTheme.textMuted)),
        ),
      ],
    );
    if (!boxed) {
      return content;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: spCardBorder),
      ),
      child: content,
    );
  }
}

/// Live slot counts from `establishment_occupancy/{id}` (kept by the
/// updateOccupancy Cloud Function): vehicles checked in, per type.
class SpOccupancy {
  const SpOccupancy({required this.car, required this.motorcycle});

  static SpOccupancy? fromDoc(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final Map<String, dynamic>? data = doc?.data();
    if (data == null) return null;
    final dynamic occupied = data['occupied'];
    final Map<dynamic, dynamic> map = occupied is Map
        ? occupied
        : <dynamic, dynamic>{};
    return SpOccupancy(
      car: ((map['car'] as num?) ?? 0).toInt(),
      motorcycle: ((map['motorcycle'] as num?) ?? 0).toInt(),
    );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(
    String establishmentId,
  ) => FirebaseFirestore.instance
      .collection('establishment_occupancy')
      .doc(establishmentId)
      .snapshots();

  final int car;
  final int motorcycle;

  int get total => car + motorcycle;

  int of(String vehicleKey) => vehicleKey == 'motorcycle' ? motorcycle : car;
}

/// [SpSlotsCard] fed by the live occupancy doc. Until that doc exists (it is
/// created on the first check-in, or by "Rebuild statistics") it falls back
/// to [fallbackOccupied].
class SpLiveSlotsCard extends StatelessWidget {
  const SpLiveSlotsCard({
    super.key,
    required this.establishmentId,
    required this.totalSlots,
    required this.fallbackOccupied,
    this.carSlots = 0,
    this.motorcycleSlots = 0,
  });

  final String establishmentId;
  final int totalSlots;
  final int fallbackOccupied;
  final int carSlots;
  final int motorcycleSlots;

  @override
  Widget build(BuildContext context) {
    if (establishmentId.isEmpty) {
      return SpSlotsCard(
        totalSlots: totalSlots,
        occupied: fallbackOccupied,
        carSlots: carSlots,
        motorcycleSlots: motorcycleSlots,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: SpOccupancy.watch(establishmentId),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final SpOccupancy? live = SpOccupancy.fromDoc(snapshot.data);
            return SpSlotsCard(
              totalSlots: totalSlots,
              occupied: live?.total ?? fallbackOccupied,
              carSlots: carSlots,
              motorcycleSlots: motorcycleSlots,
              carOccupied: live?.car,
              motorcycleOccupied: live?.motorcycle,
            );
          },
    );
  }
}

/// Occupancy ring with occupied/available/capacity legend and a car vs
/// motorcycle split (free of capacity when per-type counts are known).
class SpSlotsCard extends StatelessWidget {
  const SpSlotsCard({
    super.key,
    required this.totalSlots,
    required this.occupied,
    this.carSlots = 0,
    this.motorcycleSlots = 0,
    this.carOccupied,
    this.motorcycleOccupied,
  });

  final int totalSlots;
  final int occupied;
  final int carSlots;
  final int motorcycleSlots;
  final int? carOccupied;
  final int? motorcycleOccupied;

  @override
  Widget build(BuildContext context) {
    final int available = (totalSlots - occupied).clamp(0, totalSlots);
    final double occupancy = totalSlots == 0
        ? 0
        : (occupied / totalSlots).clamp(0, 1).toDouble();
    final (Color barColor, String levelLabel) = occupancy >= 0.9
        ? (spDeniedColor, 'Almost full')
        : occupancy >= 0.6
        ? (const Color(0xFFE09B12), 'Filling up')
        : (spEntryColor, 'Plenty of space');

    return SpSectionCard(
      icon: Icons.local_parking_rounded,
      title: 'Parking Slots',
      trailing: totalSlots > 0
          ? SpChip(label: levelLabel, color: barColor)
          : null,
      child: totalSlots == 0
          ? Text(
              'No slot capacity set for this facility yet.',
              style: TextStyle(color: AppTheme.textMuted),
            )
          : Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 104,
                      height: 104,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: occupancy,
                              strokeWidth: 10,
                              strokeCap: StrokeCap.round,
                              backgroundColor: AppTheme.border,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                barColor,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(occupancy * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                              Text(
                                'occupied',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _legend(barColor, 'Occupied', occupied),
                          const SizedBox(height: 10),
                          _legend(AppTheme.border, 'Available', available),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1, color: AppTheme.border),
                          ),
                          _legend(
                            AppTheme.textDark,
                            'Total capacity',
                            totalSlots,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (carSlots > 0 || motorcycleSlots > 0) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _typeChip(
                        Icons.directions_car_rounded,
                        carOccupied == null ? 'Car slots' : 'Car free',
                        carSlots,
                        occupiedOfType: carOccupied,
                      ),
                      const SizedBox(width: 8),
                      _typeChip(
                        Icons.two_wheeler_rounded,
                        motorcycleOccupied == null
                            ? 'Motorcycle'
                            : 'Motorcycle free',
                        motorcycleSlots,
                        occupiedOfType: motorcycleOccupied,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _legend(Color color, String label, int value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  Widget _typeChip(
    IconData icon,
    String label,
    int count, {
    int? occupiedOfType,
  }) {
    final String value = occupiedOfType == null
        ? '$count'
        : '${(count - occupiedOfType).clamp(0, count)}/$count';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// License-plate style badge.
class SpPlateBadge extends StatelessWidget {
  const SpPlateBadge({super.key, required this.plate});

  final String plate;

  @override
  Widget build(BuildContext context) {
    final String text = plate.trim().toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: Text(
        text.isEmpty ? 'NO PLATE' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppTheme.textDark,
        ),
      ),
    );
  }
}

/// One gate scan (`activity_logs` doc): entry/exit/denied icon, plate, status,
/// time, who scanned it, stay length, overtime and ticket number.
class SpActivityCard extends StatelessWidget {
  const SpActivityCard({
    super.key,
    required this.data,
    this.showDate = false,
    this.staffNames,
    this.onTap,
  });

  final Map<String, dynamic> data;

  /// Prefix the scan time with its date (for lists spanning several days).
  final bool showDate;

  /// Current staff uid-to-name map. When given, a staff member missing from
  /// it is marked as removed.
  final Map<String, String>? staffNames;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isExit = spLogScanType(data) == 'exit';
    final bool allowed = spIsAllowedLog(data);
    final bool inside = spIsInsideLog(data);
    final String reason = ((data['decisionReason'] as String?) ?? '').trim();
    final DateTime? time = spParseDateTime(data['timestamp']);
    final int? elapsedSeconds = (data['elapsedSeconds'] as num?)?.toInt();
    final int? billableHours = (data['billableHours'] as num?)?.toInt();
    final int overtimeHours = ((data['overtimeHours'] as num?) ?? 0).toInt();
    final double overtimeAmount = ((data['overtimeAmount'] as num?) ?? 0)
        .toDouble();
    final String transactionId = ((data['transactionId'] as String?) ?? '')
        .trim();
    final String? staffName = spLogStaffName(data, staffNames);
    final String staffId = ((data['staffId'] as String?) ?? '').trim();
    final bool staffRemoved =
        staffNames != null &&
        staffId.isNotEmpty &&
        !staffNames!.containsKey(staffId);

    final Color accent = !allowed
        ? spDeniedColor
        : isExit
        ? spExitColor
        : spEntryColor;
    final IconData icon = !allowed
        ? Icons.block_rounded
        : isExit
        ? Icons.logout_rounded
        : Icons.login_rounded;
    final String typeLabel = isExit ? 'Exit' : 'Entry';
    final (String chipLabel, Color chipColor) = !allowed
        ? ('Denied', spDeniedColor)
        : inside
        ? ('Inside', spInsideColor)
        : isExit
        ? ('Exited', spExitColor)
        : ('Checked out', AppTheme.textMuted);
    final String timeText = time == null
        ? ''
        : showDate
        ? ' · ${spFormatDate(time)}, ${spFormatClockTime(time)}'
        : ' · ${spFormatClockTime(time)}';

    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SpPlateBadge(
                        plate: (data['vehiclePlate'] as String?) ?? '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SpChip(label: chipLabel, color: chipColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$typeLabel scan$timeText',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              if (staffName != null) ...<Widget>[
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.badge_outlined,
                      size: 13,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'By $staffName${staffRemoved ? ' (removed)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isExit && allowed && elapsedSeconds != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  'Stayed ${spFormatDuration(Duration(seconds: elapsedSeconds))}'
                  '${billableHours == null ? '' : ' · Billed ${billableHours}h'}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
              if (overtimeHours > 0) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warningSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    overtimeAmount > 0
                        ? 'Overtime ${overtimeHours}h · collect PHP ${overtimeAmount.toStringAsFixed(2)} cash'
                        : 'Overtime ${overtimeHours}h · rate missing',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: spInsideColor,
                    ),
                  ),
                ),
              ] else if (reason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    color: allowed ? AppTheme.textMuted : spDeniedColor,
                  ),
                ),
              ],
              if (transactionId.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Ticket #${spShortTicketId(transactionId)}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (onTap != null)
          Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: spCardBorder),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: content),
        ),
      ),
    );
  }
}

/// Last 8 characters of a ticket id, as shown on gate cards.
String spShortTicketId(String transactionId) => transactionId.length > 8
    ? transactionId.substring(transactionId.length - 8)
    : transactionId;

/// Date picker pill ("Today" / "Sep 23, 2026").
class SpDateButton extends StatelessWidget {
  const SpDateButton({super.key, required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: spCardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppTheme.textDark,
              ),
              const SizedBox(width: 6),
              Text(
                spSameDate(date, DateTime.now()) ? 'Today' : spFormatDate(date),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple vertical bar chart. [labels] sit under the bars; with many bars
/// only every [labelEvery]-th label is drawn so they don't collide. The
/// highest bar is marked with its value.
class SpBarChart extends StatelessWidget {
  const SpBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.formatValue,
    this._color,
    this.height = 170,
    this.labelEvery = 1,
  });

  final List<double> values;
  final List<String> labels;
  final String Function(double value) formatValue;
  final Color? _color;
  Color get color => _color ?? spExitColor;
  final double height;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final double maxValue = values.fold<double>(
      0,
      (double best, double value) => value > best ? value : best,
    );
    final int peakIndex = maxValue <= 0 ? -1 : values.indexOf(maxValue);
    final double gap = values.length > 20 ? 2 : (values.length > 10 ? 4 : 8);

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gap / 2),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) {
                          final double labelSpace = i == peakIndex ? 18 : 0;
                          final double usable = (box.maxHeight - labelSpace)
                              .clamp(0, double.infinity);
                          final double barHeight = maxValue <= 0
                              ? 3
                              : (values[i] / maxValue * usable).clamp(
                                  3,
                                  usable,
                                );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (i == peakIndex)
                                SizedBox(
                                  height: labelSpace,
                                  child: OverflowBox(
                                    minWidth: 0,
                                    maxWidth: 80,
                                    child: Text(
                                      formatValue(values[i]),
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: values[i] <= 0
                                      ? AppTheme.border
                                      : (i == peakIndex
                                            ? color
                                            : color.withValues(alpha: 0.55)),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(
                                      values.length > 20 ? 3 : 6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 6),
          // Fixed height: an unbounded label row makes the overflow boxes
          // below infinitely tall and breaks layout on every frame.
          SizedBox(
            height: 14,
            child: Row(
              children: [
                for (int i = 0; i < labels.length; i++)
                  Expanded(
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: 60,
                      child: Text(
                        i % labelEvery == 0 ? labels[i] : '',
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Short money label for chart peaks and tiles, e.g. "PHP 1.2k".
String spCompactPeso(double value) {
  if (value >= 1000000) return 'PHP ${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return 'PHP ${(value / 1000).toStringAsFixed(1)}k';
  return 'PHP ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

/// Keeps Firestore streams alive across rebuilds. Creating `.snapshots()`
/// inline in `build` hands StreamBuilder a new stream on every setState, so
/// it resubscribes and flashes its loading state (the whole tab "refreshes"
/// when a filter or chip changes). Call [cachedStream] with a key that
/// includes any ids the query depends on.
mixin SpStreamCache<W extends StatefulWidget> on State<W> {
  final Map<String, Stream<dynamic>> _spStreams = <String, Stream<dynamic>>{};

  Stream<T> cachedStream<T>(String key, Stream<T> Function() create) {
    return _spStreams.putIfAbsent(key, create) as Stream<T>;
  }

  /// Builds from one [day] of a facility's gate logs plus its still-open
  /// entries, so screens never download the whole scan history. The streams
  /// are keyed by date, so a new [day] (or midnight passing) re-queries.
  Widget withDayLogs(
    String facilityId,
    DateTime day, {
    required Widget Function(BuildContext context, SpDayLogs logs) builder,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'inside_$facilityId',
        () => spInsideLogsQuery(facilityId).snapshots(),
      ),
      builder: (BuildContext context, insideSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: cachedStream(
            'day_${facilityId}_${spDayKey(day)}',
            () => spDayLogsQuery(facilityId, day).snapshots(),
          ),
          builder: (BuildContext context, daySnapshot) => builder(
            context,
            SpDayLogs(
              logs: spDocsData(daySnapshot),
              insideLogs: spNewestFirst(spDocsData(insideSnapshot)),
              loaded: daySnapshot.hasData,
              error: daySnapshot.error ?? insideSnapshot.error,
            ),
          ),
        );
      },
    );
  }
}

/// One day of a facility's gate logs (newest first) plus the entry logs
/// still open from any day, for "inside now".
class SpDayLogs {
  const SpDayLogs({
    required this.logs,
    required this.insideLogs,
    required this.loaded,
    this.error,
  });

  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> insideLogs;

  /// Whether the day's logs have arrived.
  final bool loaded;
  final Object? error;
}

/// Sorts gate logs newest first; pending server timestamps count as now.
List<Map<String, dynamic>> spNewestFirst(List<Map<String, dynamic>> logs) {
  final DateTime now = DateTime.now();
  return logs..sort(
    (Map<String, dynamic> a, Map<String, dynamic> b) =>
        (spParseDateTime(b['timestamp']) ?? now).compareTo(
          spParseDateTime(a['timestamp']) ?? now,
        ),
  );
}

/// Equal-width segmented filter (grey track, white pill on the selected
/// option), so options with different label lengths still line up evenly.
class SpSegmentedControl<T> extends StatelessWidget {
  const SpSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Value and label for each segment, in display order.
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        children: [
          for (final (T value, String label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (value != selected) onChanged(value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppTheme.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    boxShadow: value == selected
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: value == selected
                          ? AppTheme.textDark
                          : AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
