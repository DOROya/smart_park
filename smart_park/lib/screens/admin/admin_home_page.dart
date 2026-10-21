import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/facility_status.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_profile_view.dart';
import '../auth/sign_in_screen.dart';

part 'admin_home_page_fragments.dart';
part 'admin_facility_review.dart';
part 'admin_user_directory.dart';
part 'admin_finance_series.dart';

enum _AdminTab { dashboard, facility, users, finance, settings }

enum _FacilitySortOption { pendingFirst, newest, oldest }

enum _UserRoleFilter { all, driver, parkingOwner }

enum _FinanceRangeFilter { all, month, quarter, year }

/// A status change offered in the establishment review dialog.
typedef _StatusAction = ({
  String status,
  String label,
  IconData icon,
  Color color,
  bool primary,
});

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with SpStreamCache<AdminHomePage> {
  _AdminTab _selectedTab = _AdminTab.dashboard;
  _FacilitySortOption _facilitySort = _FacilitySortOption.pendingFirst;
  _UserRoleFilter _userRoleFilter = _UserRoleFilter.all;
  _FinanceRangeFilter _financeRange = _FinanceRangeFilter.month;

  bool _railExtended = false;
  bool _rebuildingStats = false;

  /// How many facilities each review panel shows, keyed by panel title.
  final Map<String, int> _facilityPanelLimits = <String, int>{};

  String _facilitySearchQuery = '';
  String _usersSearchQuery = '';

  final TextEditingController _facilitySearchController =
      TextEditingController();
  final TextEditingController _usersSearchController = TextEditingController();
  Map<String, Map<String, dynamic>> _establishmentDetailsById =
      <String, Map<String, dynamic>>{};

  @override
  void dispose() {
    _facilitySearchController.dispose();
    _usersSearchController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  String _readText(dynamic value, {String fallback = 'Not provided'}) {
    final String text = (value as String?)?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Map<String, dynamic> _mergedEstablishmentData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> details =
        _establishmentDetailsById[doc.id] ?? <String, dynamic>{};
    return <String, dynamic>{
      ...doc.data(),
      ...details,
      'establishmentID': doc.id,
    };
  }

  bool _isPriorityUserRole(String role) {
    final String normalizedRole = _normalize(role);
    return normalizedRole == 'driver' || normalizedRole == 'parking owner';
  }

  bool _matchesUserRole(String role) {
    final String normalizedRole = _normalize(role);
    return switch (_userRoleFilter) {
      _UserRoleFilter.all => _isPriorityUserRole(normalizedRole),
      _UserRoleFilter.driver => normalizedRole == 'driver',
      _UserRoleFilter.parkingOwner => normalizedRole == 'parking owner',
    };
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) {
    final String query = _normalize(_usersSearchQuery);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = users
        .where((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic> data = doc.data();
          final String firstName = (data['firstName'] as String?) ?? '';
          final String lastName = (data['lastName'] as String?) ?? '';
          final String email = (data['email'] as String?) ?? '';
          final String role = (data['role'] as String?) ?? '';

          if (!_isPriorityUserRole(role)) {
            return false;
          }

          if (!_matchesUserRole(role)) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          final String haystack = _normalize(
            '$firstName $lastName $email $role',
          );
          return haystack.contains(query);
        })
        .toList();

    filtered.sort((
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) {
      final DateTime aDate =
          _parseDateTime(a.data()['createdAt']) ??
          _parseDateTime(a.data()['createdAtClient']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          _parseDateTime(b.data()['createdAt']) ??
          _parseDateTime(b.data()['createdAtClient']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return filtered;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredEstablishments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    final String query = _normalize(_facilitySearchQuery);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered =
        establishments.where((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic> data = _mergedEstablishmentData(doc);
          if (query.isEmpty) {
            return true;
          }

          final String name = (data['name'] as String?) ?? '';
          final String address = (data['address'] as String?) ?? '';
          final String ownerFirstName =
              (data['ownerFirstName'] as String?) ?? '';
          final String ownerLastName = (data['ownerLastName'] as String?) ?? '';
          final String ownerEmail = (data['ownerEmail'] as String?) ?? '';
          final String haystack = _normalize(
            '$name $address $ownerFirstName $ownerLastName $ownerEmail',
          );
          return haystack.contains(query);
        }).toList();

    int statusPriority(String status) {
      return switch (_normalize(status)) {
        'pending' => 0,
        'approved' => 1,
        'suspended' => 2,
        'rejected' => 3,
        'deactivated' => 4,
        _ => 5,
      };
    }

    filtered.sort((
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) {
      final DateTime aDate =
          _parseDateTime(_mergedEstablishmentData(a)['createdAt']) ??
          _parseDateTime(_mergedEstablishmentData(a)['createdAtClient']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          _parseDateTime(_mergedEstablishmentData(b)['createdAt']) ??
          _parseDateTime(_mergedEstablishmentData(b)['createdAtClient']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      switch (_facilitySort) {
        case _FacilitySortOption.newest:
          return bDate.compareTo(aDate);
        case _FacilitySortOption.oldest:
          return aDate.compareTo(bDate);
        case _FacilitySortOption.pendingFirst:
          final int byStatus =
              statusPriority(
                (_mergedEstablishmentData(a)['status'] as String?) ?? 'pending',
              ).compareTo(
                statusPriority(
                  (_mergedEstablishmentData(b)['status'] as String?) ??
                      'pending',
                ),
              );
          if (byStatus != 0) {
            return byStatus;
          }
          return bDate.compareTo(aDate);
      }
    });

    return filtered;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingEstablishments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    return establishments.where((
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ) {
      final String status =
          ((_mergedEstablishmentData(doc)['status'] as String?) ?? 'pending')
              .toLowerCase();
      return status == 'pending';
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _approvedEstablishments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    return establishments.where((
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ) {
      final String status =
          ((_mergedEstablishmentData(doc)['status'] as String?) ?? 'pending')
              .toLowerCase();
      return status == 'approved';
    }).toList();
  }

  DateTime? _financeCutoff() {
    final DateTime now = DateTime.now();
    return switch (_financeRange) {
      _FinanceRangeFilter.all => null,
      _FinanceRangeFilter.month => DateTime(now.year, now.month - 1, now.day),
      _FinanceRangeFilter.quarter => DateTime(now.year, now.month - 3, now.day),
      _FinanceRangeFilter.year => DateTime(now.year - 1, now.month, now.day),
    };
  }

  List<_DayStat> _filteredPayments(List<_DayStat> days) {
    final DateTime? cutoff = _financeCutoff();
    if (cutoff == null) {
      return List<_DayStat>.from(days);
    }
    final DateTime cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return days.where((_DayStat d) => !d.day.isBefore(cutoffDay)).toList();
  }

  String _financeRangeLabel() {
    return switch (_financeRange) {
      _FinanceRangeFilter.all => 'All Time',
      _FinanceRangeFilter.month => 'Last 30 Days',
      _FinanceRangeFilter.quarter => 'Last 90 Days',
      _FinanceRangeFilter.year => 'Last 12 Months',
    };
  }

  String _formatSingleRateVal(dynamic val) {
    if (val is Map) {
      final String initial = (val['initial'] ?? val['hourly'] ?? '-')
          .toString();
      final String succH = (val['succeedingHour'] ?? '').toString();
      final String succD = (val['succeedingDaily'] ?? val['daily'] ?? '')
          .toString();
      final String weekly = (val['weekly'] ?? '').toString();
      final String monthly = (val['monthly'] ?? '').toString();
      String res = initial;
      if (succH.isNotEmpty) res += ' (+$succH/hr)';
      if (succD.isNotEmpty) res += ' ($succD/day)';
      if (weekly.isNotEmpty) res += ' ($weekly/week)';
      if (monthly.isNotEmpty) res += ' ($monthly/month)';
      return res;
    }
    return (val ?? '-').toString();
  }

  String _formatRates(dynamic value) {
    if (value == null) {
      return 'Not provided';
    }
    if (value is String) {
      final String text = value.trim();
      return text.isEmpty ? 'Not provided' : text;
    }
    if (value is Map) {
      final Map<dynamic, dynamic> map = value;
      final String car = _formatSingleRateVal(map['car']);
      final String motorcycle = _formatSingleRateVal(map['motorcycle']);
      return 'Car: $car, Motorcycle: $motorcycle';
    }
    return value.toString();
  }

  /// Recomputes `stats_daily` from every payment on the server. Needed once
  /// after the stats functions are first deployed (older payments predate
  /// them), and whenever the totals look off.
  Future<void> _rebuildStats() async {
    if (_rebuildingStats) return;
    setState(() => _rebuildingStats = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final HttpsCallableResult<dynamic> result =
          await FirebaseFunctions.instanceFor(
            region: 'asia-southeast1',
          ).httpsCallable('rebuildDailyStats').call<dynamic>();
      final Map<dynamic, dynamic> data = result.data is Map
          ? result.data as Map<dynamic, dynamic>
          : <dynamic, dynamic>{};
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Statistics rebuilt from ${data['paymentCount'] ?? 0} payments.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Unable to rebuild statistics.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _rebuildingStats = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }

    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (Route<dynamic> route) => false,
      ),
    );
  }

  Future<void> _updateEstablishmentStatus(
    String establishmentId,
    String status, {
    String? rejectionReason,
    String? restrictionReason,
  }) async {
    final Map<String, dynamic> updates = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // `rejectionReason` holds the admin's note for any status the owner
    // should get an explanation for: rejected, suspended or deactivated.
    if (const <String>{
      'rejected',
      'suspended',
      'deactivated',
    }.contains(status.toLowerCase())) {
      final String trimmedReason = (rejectionReason ?? '').trim();
      updates['rejectionReason'] = trimmedReason.isEmpty ? null : trimmedReason;
    } else {
      updates['rejectionReason'] = null;
    }
    // The picked reason only applies while the facility is pulled.
    updates['restrictionReason'] =
        status == 'suspended' || status == 'deactivated'
        ? restrictionReason
        : null;

    await FirebaseFirestore.instance
        .collection('establishment_details')
        .doc(establishmentId)
        .set(updates, SetOptions(merge: true));
  }

  /// `establishment_details` merged with `establishment_private` (where
  /// business documents live, readable only by the owner and admins).
  Stream<Map<String, dynamic>> _reviewDataStream(String establishmentId) {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    Map<String, dynamic> details = <String, dynamic>{};
    Map<String, dynamic> private = <String, dynamic>{};
    late final StreamController<Map<String, dynamic>> controller;
    final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
    subscriptions =
        <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];
    void emit() => controller.add(<String, dynamic>{...details, ...private});
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        subscriptions
          ..add(
            db
                .collection('establishment_details')
                .doc(establishmentId)
                .snapshots()
                .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
                  details = snap.data() ?? <String, dynamic>{};
                  emit();
                }, onError: controller.addError),
          )
          ..add(
            db
                .collection('establishment_private')
                .doc(establishmentId)
                .snapshots()
                .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
                  private = snap.data() ?? <String, dynamic>{};
                  emit();
                }, onError: controller.addError),
          );
      },
      onCancel: () async {
        for (final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
            sub
            in subscriptions) {
          await sub.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  void _showDocumentViewer(String url) {
    showDialog<void>(
      context: context,
      builder: (BuildContext viewerContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(viewerContext).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatReviewDate(DateTime date) {
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

  List<String> _stringList(dynamic value) {
    return ((value as List<dynamic>?) ?? <dynamic>[])
        .whereType<String>()
        .where((String url) => url.trim().isNotEmpty)
        .toList();
  }

  Widget _buildReviewStatusChip(String status, {required bool resubmitted}) {
    final (
      Color background,
      Color foreground,
      String label,
    ) = switch (_normalize(status)) {
      'approved' => (AppTheme.successSoft, AppTheme.success, 'Approved'),
      'rejected' => (AppTheme.dangerSoft, AppTheme.danger, 'Rejected'),
      'suspended' => (AppTheme.warningSoft, AppTheme.warning, 'Suspended'),
      'deactivated' => (AppTheme.surfaceAlt, AppTheme.textMuted, 'Deactivated'),
      _ => (
        AppTheme.warningSoft,
        AppTheme.warning,
        resubmitted ? 'Resubmitted' : 'Pending Review',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildReviewSection({
    required IconData icon,
    required String title,
    String? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.textDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildReviewField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textDark,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<String> urls, {double size = 84}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final String url in urls)
          GestureDetector(
            onTap: () => _showDocumentViewer(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: SizedBox(
                width: size,
                height: size,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, Widget child, ImageChunkEvent? progress) {
                    if (progress == null) {
                      return child;
                    }
                    return ColoredBox(
                      color: AppTheme.surfaceAlt,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: AppTheme.border,
                    child: Icon(Icons.broken_image_rounded),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBusinessDocuments(List<String> documentUrls) {
    if (documentUrls.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dangerSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.danger),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No business documents submitted. Ask the owner to upload '
                'proof of business before approving.',
                style: TextStyle(fontSize: 12, color: AppTheme.danger),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageGrid(documentUrls),
        const SizedBox(height: 6),
        Text(
          'Tap a document to view it full screen.',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Future<bool> _confirmApproveWithoutDocuments(
    BuildContext dialogContext,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          title: const Text('Approve without documents?'),
          content: const Text(
            'This establishment has no business documents on file. '
            'Approve it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Confirms suspending or deactivating a facility, both of which pull it
  /// from drivers and stop ticket sales.
  Future<bool> _confirmRestrictFacility(
    BuildContext dialogContext,
    String newStatus,
    String reason,
  ) async {
    final bool suspend = newStatus == 'suspended';
    final bool? confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          title: Text(
            suspend ? 'Suspend this facility?' : 'Deactivate this facility?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Reason: ',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                      TextSpan(
                        text: reason,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                suspend
                    ? 'It will be hidden from drivers and cannot sell tickets '
                          'until you reinstate it. Its gate will refuse every '
                          'entry, and drivers will see their tickets for it as '
                          'invalid. Vehicles already inside can still exit.'
                    : 'It will be removed from SmartPark and cannot sell '
                          'tickets. Its gate will refuse every entry, and '
                          'drivers will see their tickets for it as invalid. '
                          'Vehicles already inside can still exit. You can '
                          'reactivate it later.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: suspend ? AppTheme.warning : AppTheme.danger,
              ),
              child: Text(suspend ? 'Suspend' : 'Deactivate'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Predefined reasons for suspending or deactivating a facility, shown
  /// above the optional note. One must be picked before either action.
  Widget _buildRestrictionReasonPicker({
    required String? selected,
    required bool missing,
    required bool enabled,
    required ValueChanged<String?> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Reason for Suspending or Deactivating ',
            children: [
              TextSpan(
                text: '*',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Shown to the owner and to drivers holding tickets here.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final String reason in kRestrictionReasons)
              ChoiceChip(
                label: Text(reason),
                selected: selected == reason,
                showCheckmark: false,
                avatar: selected == reason
                    ? Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppTheme.onAccent,
                      )
                    : null,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected == reason
                      ? AppTheme.onAccent
                      : AppTheme.textDark,
                ),
                selectedColor: AppTheme.accent,
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: selected == reason
                      ? AppTheme.accent
                      : missing
                      ? AppTheme.dangerBorder
                      : AppTheme.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onSelected: enabled
                    ? (bool on) => onSelected(on ? reason : null)
                    : null,
              ),
          ],
        ),
        if (missing) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected == 'Other'
                      ? 'Describe the reason in the details box below.'
                      : 'Pick a reason first.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// One button in the review dialog's action row: filled for the primary
  /// action, outlined otherwise.
  Widget _buildStatusActionButton(
    _StatusAction action, {
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    final Widget icon = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: 18);
    final Widget label = Text(
      action.label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radius),
    );
    const EdgeInsets padding = EdgeInsets.symmetric(vertical: 12);

    if (action.primary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: action.color,
          foregroundColor: AppTheme.onAccent,
          elevation: 0,
          padding: padding,
          shape: shape,
        ),
        icon: icon,
        label: label,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: action.color,
        side: BorderSide(color: action.color),
        padding: padding,
        shape: shape,
      ),
      icon: icon,
      label: label,
    );
  }

  Future<void> _showEstablishmentReviewDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final TextEditingController rejectionReasonController =
        TextEditingController();
    // The status being saved, so only that button shows a spinner.
    String? submittingStatus;
    // Predefined reason for suspending or deactivating, and whether the
    // admin tried to without one (or picked "Other" with no details).
    String? restrictionReason;
    bool reasonMissing = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Streams the details and private docs so documents the owner
        // uploads while the dialog is open show up without reopening it.
        return StreamBuilder<Map<String, dynamic>>(
          stream: _reviewDataStream(doc.id),
          builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
            final Map<String, dynamic> data = <String, dynamic>{
              ..._mergedEstablishmentData(doc),
              ...?snapshot.data,
            };
            final String ownerName =
                '${(data['ownerFirstName'] as String?) ?? ''} ${(data['ownerLastName'] as String?) ?? ''}'
                    .trim();
            final String status = (data['status'] as String?) ?? 'pending';
            final bool resubmitted = data['resubmittedAt'] != null;
            final DateTime? submittedAt =
                _parseDateTime(data['resubmittedAt']) ??
                _parseDateTime(data['createdAt']);
            final String? previousRestriction = facilityRestrictionReason(data);
            final String previousRejection =
                ((data['rejectionReason'] as String?) ?? '').trim();
            final Map<dynamic, dynamic> rates =
                (data['rates'] ?? data['ratesByType']) is Map
                ? (data['rates'] ?? data['ratesByType'])
                      as Map<dynamic, dynamic>
                : <dynamic, dynamic>{};
            final List<String> photoUrls = _stringList(data['photoUrls']);
            final List<String> documentUrls = _stringList(
              data['businessDocumentUrls'],
            );

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                final String current = _normalize(status);

                Future<void> submit(String newStatus) async {
                  bool confirmed = true;
                  if (newStatus == 'suspended' || newStatus == 'deactivated') {
                    final String? reason = restrictionReason;
                    if (reason == null ||
                        (reason == 'Other' &&
                            rejectionReasonController.text.trim().isEmpty)) {
                      setDialogState(() => reasonMissing = true);
                      return;
                    }
                    confirmed = await _confirmRestrictFacility(
                      dialogContext,
                      newStatus,
                      reason == 'Other'
                          ? rejectionReasonController.text.trim()
                          : reason,
                    );
                  } else if (newStatus == 'approved' &&
                      documentUrls.isEmpty &&
                      (current == 'pending' || current == 'rejected')) {
                    // Reinstating a facility that was already approved
                    // once doesn't need the missing-documents warning.
                    confirmed = await _confirmApproveWithoutDocuments(
                      dialogContext,
                    );
                  }
                  if (!confirmed) {
                    return;
                  }
                  setDialogState(() => submittingStatus = newStatus);
                  try {
                    await _updateEstablishmentStatus(
                      doc.id,
                      newStatus,
                      rejectionReason: rejectionReasonController.text,
                      restrictionReason: restrictionReason,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(switch (newStatus) {
                            'approved' =>
                              current == 'pending' || current == 'rejected'
                                  ? 'Establishment approved.'
                                  : 'Establishment reinstated.',
                            'suspended' => 'Establishment suspended.',
                            'deactivated' => 'Establishment deactivated.',
                            _ => 'Establishment rejected.',
                          }),
                        ),
                      );
                    }
                  } catch (error) {
                    setDialogState(() => submittingStatus = null);
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            friendlyError(
                              error,
                              fallback: 'Unable to update status.',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                }

                // What the admin can do depends on where the facility
                // stands: review a submission, restrict a live facility, or
                // lift a restriction.
                final bool isSubmitting = submittingStatus != null;
                final List<_StatusAction> actions = switch (current) {
                  'approved' => <_StatusAction>[
                    (
                      status: 'deactivated',
                      label: 'Deactivate',
                      icon: Icons.block_rounded,
                      color: AppTheme.danger,
                      primary: false,
                    ),
                    (
                      status: 'suspended',
                      label: 'Suspend',
                      icon: Icons.pause_circle_outline_rounded,
                      color: AppTheme.warning,
                      primary: false,
                    ),
                  ],
                  'suspended' => <_StatusAction>[
                    (
                      status: 'deactivated',
                      label: 'Deactivate',
                      icon: Icons.block_rounded,
                      color: AppTheme.danger,
                      primary: false,
                    ),
                    (
                      status: 'approved',
                      label: 'Reinstate',
                      icon: Icons.play_circle_outline_rounded,
                      color: AppTheme.accent,
                      primary: true,
                    ),
                  ],
                  'deactivated' => <_StatusAction>[
                    (
                      status: 'approved',
                      label: 'Reactivate',
                      icon: Icons.play_circle_outline_rounded,
                      color: AppTheme.accent,
                      primary: true,
                    ),
                  ],
                  _ => <_StatusAction>[
                    (
                      status: 'rejected',
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      color: AppTheme.danger,
                      primary: false,
                    ),
                    (
                      status: 'approved',
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      color: AppTheme.accent,
                      primary: true,
                    ),
                  ],
                };
                final bool restricting =
                    current == 'approved' || current == 'suspended';
                final String noteTitle = switch (current) {
                  'suspended' => 'Suspension Reason',
                  'deactivated' => 'Deactivation Reason',
                  _ => 'Previous Rejection Reason',
                };

                return Dialog(
                  backgroundColor: AppTheme.background,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                      maxWidth: 720,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header: which establishment and where it stands.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(
                                    alpha: 0.25,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radius,
                                  ),
                                ),
                                child: Icon(
                                  Icons.local_parking_rounded,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _readText(
                                        data['name'],
                                        fallback: 'Unnamed Establishment',
                                      ),
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _readText(
                                        data['address'],
                                        fallback: 'No address',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        _buildReviewStatusChip(
                                          status,
                                          resubmitted: resubmitted,
                                        ),
                                        if (submittedAt != null)
                                          Text(
                                            '${resubmitted ? 'Resubmitted' : 'Submitted'} '
                                            '${_formatReviewDate(submittedAt)}',
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
                              IconButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildReviewSection(
                                  icon: Icons.person_outline_rounded,
                                  title: 'Registrant',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildReviewField(
                                        'Name',
                                        ownerName.isEmpty
                                            ? 'Unknown Owner'
                                            : ownerName,
                                      ),
                                      _buildReviewField(
                                        'Email',
                                        _readText(
                                          data['ownerEmail'],
                                          fallback: 'N/A',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildReviewSection(
                                  icon: Icons.storefront_outlined,
                                  title: 'Facility Details',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildReviewField(
                                        'Operating Hours',
                                        _readText(data['operatingHours']),
                                      ),
                                      _buildReviewField(
                                        'Slots',
                                        'Car: ${((data['slotCounts'] as Map?)?['car'] as num?) ?? 0}\n'
                                            'Motorcycle: ${((data['slotCounts'] as Map?)?['motorcycle'] as num?) ?? 0}',
                                      ),
                                      _buildReviewField(
                                        'Rates',
                                        rates.isEmpty
                                            ? _formatRates(
                                                data['rates'] ??
                                                    data['ratesByType'],
                                              )
                                            : 'Car: ${_formatSingleRateVal(rates['car'])}\n'
                                                  'Motorcycle: ${_formatSingleRateVal(rates['motorcycle'])}',
                                      ),
                                      _buildReviewField(
                                        'Policies',
                                        _readText(data['policies']),
                                      ),
                                    ],
                                  ),
                                ),
                                if (photoUrls.isNotEmpty)
                                  _buildReviewSection(
                                    icon: Icons.photo_library_outlined,
                                    title: 'Facility Photos',
                                    trailing: '${photoUrls.length}',
                                    child: _buildImageGrid(photoUrls),
                                  ),
                                _buildReviewSection(
                                  icon: Icons.description_outlined,
                                  title: 'Business Documents',
                                  trailing: documentUrls.isEmpty
                                      ? null
                                      : '${documentUrls.length} submitted',
                                  child: _buildBusinessDocuments(documentUrls),
                                ),
                                if ((current == 'rejected' ||
                                        current == 'suspended' ||
                                        current == 'deactivated') &&
                                    (previousRejection.isNotEmpty ||
                                        previousRestriction != null))
                                  _buildReviewSection(
                                    icon: Icons.history_rounded,
                                    title: noteTitle,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (previousRestriction != null)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              bottom: previousRejection.isEmpty
                                                  ? 0
                                                  : 6,
                                            ),
                                            child: SpChip(
                                              label: previousRestriction,
                                              color: current == 'suspended'
                                                  ? AppTheme.warning
                                                  : AppTheme.danger,
                                            ),
                                          ),
                                        if (previousRejection.isNotEmpty)
                                          Text(
                                            previousRejection,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (restricting) ...[
                                  _buildRestrictionReasonPicker(
                                    selected: restrictionReason,
                                    missing: reasonMissing,
                                    enabled: !isSubmitting,
                                    onSelected: (String? reason) =>
                                        setDialogState(() {
                                          restrictionReason = reason;
                                          reasonMissing = false;
                                        }),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (current != 'deactivated') ...[
                                  Text(
                                    restricting
                                        ? restrictionReason == 'Other'
                                              ? 'Additional Details (Required for "Other")'
                                              : 'Additional Details (Optional)'
                                        : 'Rejection Reason (Optional)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: rejectionReasonController,
                                    enabled: !isSubmitting,
                                    maxLines: 3,
                                    onChanged: (_) {
                                      if (reasonMissing) {
                                        setDialogState(
                                          () => reasonMissing = false,
                                        );
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: restricting
                                          ? 'Anything else the owner should know. Only the owner sees this note.'
                                          : 'Shown to the owner so they can fix issues before resubmitting.',
                                      hintStyle: const TextStyle(fontSize: 12),
                                      filled: true,
                                      fillColor: AppTheme.surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radius,
                                        ),
                                        borderSide: BorderSide(
                                          color: AppTheme.border,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radius,
                                        ),
                                        borderSide: BorderSide(
                                          color: AppTheme.border,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Row(
                            children: [
                              for (int i = 0; i < actions.length; i++) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _buildStatusActionButton(
                                    actions[i],
                                    busy: submittingStatus == actions[i].status,
                                    onPressed: isSubmitting
                                        ? null
                                        : () => submit(actions[i].status),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static const List<(IconData, IconData, String)> _navItems =
      <(IconData, IconData, String)>[
        (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Dashboard'),
        (Icons.apartment_outlined, Icons.apartment_rounded, 'Facility'),
        (Icons.group_outlined, Icons.group_rounded, 'Users'),
        (Icons.payments_outlined, Icons.payments_rounded, 'Finance'),
        (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
      ];

  void _selectTab(int index) {
    setState(() {
      _selectedTab = _AdminTab.values[index];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = spIsTablet(context);
    final Widget content = _buildContent(isTablet: isTablet);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: isTablet
            ? SpMenuToggleButton(
                extended: _railExtended,
                onPressed: () => setState(() => _railExtended = !_railExtended),
              )
            : null,
        titleSpacing: isTablet ? 0 : null,
        actions: [
          SpAccountAvatarButton(
            tooltip: 'Settings',
            active: _selectedTab == _AdminTab.settings,
            onTap: () => _selectTab(_AdminTab.settings.index),
            child: const Icon(Icons.shield_rounded),
          ),
          const SizedBox(width: 12),
        ],
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_parking_rounded, color: AppTheme.textDark),
            SizedBox(width: 8),
            Text(
              'SmartPark',
              style: TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isTablet
          ? null
          : NavigationBar(
              selectedIndex: _selectedTab.index,
              onDestinationSelected: _selectTab,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: <NavigationDestination>[
                for (final (IconData icon, IconData activeIcon, String label)
                    in _navItems)
                  NavigationDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(activeIcon),
                    label: label,
                  ),
              ],
            ),
      body: isTablet
          ? SpRailLayout(
              rail: SpNavRail(
                items: _navItems,
                selectedIndex: _selectedTab.index,
                onSelected: _selectTab,
                extended: _railExtended,
                onSignOut: _signOut,
              ),
              child: content,
            )
          : content,
    );
  }

  Widget _buildContent({required bool isTablet}) {
    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: cachedStream(
          'users',
          () => FirebaseFirestore.instance.collection('users').snapshots(),
        ),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> usersSnapshot,
            ) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: cachedStream(
                  'establishments',
                  () => FirebaseFirestore.instance
                      .collection('establishments')
                      .snapshots(),
                ),
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                      establishmentsSnapshot,
                    ) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: cachedStream(
                          'establishment_details',
                          () => FirebaseFirestore.instance
                              .collection('establishment_details')
                              .snapshots(),
                        ),
                        builder:
                            (
                              BuildContext context,
                              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                              establishmentDetailsSnapshot,
                            ) {
                              return StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                // Daily totals kept by the checkout Cloud
                                // Function, instead of every payment.
                                stream: cachedStream(
                                  'stats_daily',
                                  () => FirebaseFirestore.instance
                                      .collection('stats_daily')
                                      .snapshots(),
                                ),
                                builder:
                                    (
                                      BuildContext context,
                                      AsyncSnapshot<
                                        QuerySnapshot<Map<String, dynamic>>
                                      >
                                      paymentsSnapshot,
                                    ) {
                                      if (usersSnapshot.connectionState ==
                                              ConnectionState.waiting ||
                                          establishmentsSnapshot
                                                  .connectionState ==
                                              ConnectionState.waiting ||
                                          establishmentDetailsSnapshot
                                                  .connectionState ==
                                              ConnectionState.waiting ||
                                          paymentsSnapshot.connectionState ==
                                              ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }

                                      final List<
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >
                                      users =
                                          usersSnapshot.data?.docs ??
                                          <
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >[];
                                      final List<
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >
                                      establishments =
                                          establishmentsSnapshot.data?.docs ??
                                          <
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >[];
                                      final List<
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >
                                      establishmentDetails =
                                          establishmentDetailsSnapshot
                                              .data
                                              ?.docs ??
                                          <
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >[];
                                      final List<_DayStat>
                                      payments = <_DayStat>[
                                        for (final QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                            doc
                                            in paymentsSnapshot.data?.docs ??
                                                <
                                                  QueryDocumentSnapshot<
                                                    Map<String, dynamic>
                                                  >
                                                >[])
                                          ?_DayStat.fromDoc(doc),
                                      ];

                                      _establishmentDetailsById =
                                          <String, Map<String, dynamic>>{
                                            for (final QueryDocumentSnapshot<
                                                  Map<String, dynamic>
                                                >
                                                doc
                                                in establishmentDetails)
                                              doc.id: doc.data(),
                                          };

                                      final List<
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >
                                      filteredUsers = _filteredUsers(users);

                                      final List<_DayStat> financePayments =
                                          _filteredPayments(payments);

                                      final int totalUsers = users.length;
                                      final int driverCount = users.where((
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                        doc,
                                      ) {
                                        final String role =
                                            ((doc.data()['role'] as String?) ??
                                                    '')
                                                .toLowerCase();
                                        return role == 'driver';
                                      }).length;

                                      final int parkingOwnerCount =
                                          users.where((
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                            doc,
                                          ) {
                                            final String role =
                                                ((doc.data()['role']
                                                            as String?) ??
                                                        '')
                                                    .toLowerCase();
                                            return role == 'parking owner';
                                          }).length;

                                      final int establishmentCount =
                                          establishments.length;

                                      final int pendingCount =
                                          establishments.where((
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                            doc,
                                          ) {
                                            final String status =
                                                ((_mergedEstablishmentData(
                                                              doc,
                                                            )['status']
                                                            as String?) ??
                                                        'pending')
                                                    .toLowerCase();
                                            return status == 'pending';
                                          }).length;

                                      final double totalRevenue = _sumGross(
                                        payments,
                                      );
                                      final double commission = _sumCommission(
                                        payments,
                                      );
                                      final double financeRevenue = _sumGross(
                                        financePayments,
                                      );
                                      final double financeCommission =
                                          _sumCommission(financePayments);

                                      final _RevenueSeries dashboardCommission =
                                          _dailyRevenue(
                                            payments,
                                            7,
                                            amountOf: _paymentCommission,
                                          );
                                      final _RevenueSeries financeSeries =
                                          _financeRevenueSeries(
                                            financePayments,
                                          );

                                      return ListView(
                                        padding: isTablet
                                            ? const EdgeInsets.fromLTRB(
                                                24,
                                                16,
                                                24,
                                                24,
                                              )
                                            : const EdgeInsets.fromLTRB(
                                                16,
                                                10,
                                                16,
                                                24,
                                              ),
                                        children: _buildTabContent(
                                          totalUsers: totalUsers,
                                          driverCount: driverCount,
                                          parkingOwnerCount: parkingOwnerCount,
                                          filteredUsersCount:
                                              filteredUsers.length,
                                          establishmentCount:
                                              establishmentCount,
                                          pendingCount: pendingCount,
                                          totalRevenue: totalRevenue,
                                          commission: commission,
                                          paymentCount: _sumPayments(payments),
                                          dashboardCommission:
                                              dashboardCommission,
                                          financeSeries: financeSeries,
                                          financeRevenue: financeRevenue,
                                          financeCommission: financeCommission,
                                          users: users,
                                          establishments: establishments,
                                          financePayments: financePayments,
                                        ),
                                      );
                                    },
                              );
                            },
                      );
                    },
              );
            },
      ),
    );
  }
}
