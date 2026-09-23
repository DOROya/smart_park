import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'sign_in_screen.dart';

part 'admin/admin_home_page_fragments.dart';

enum _AdminTab { dashboard, facility, users, finance, settings }

enum _FacilitySortOption { pendingFirst, newest, oldest }

enum _UserRoleFilter { all, driver, parkingOwner }

enum _FinanceRangeFilter { all, week, month, quarter, year }

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  _AdminTab _selectedTab = _AdminTab.dashboard;
  _FacilitySortOption _facilitySort = _FacilitySortOption.pendingFirst;
  _UserRoleFilter _userRoleFilter = _UserRoleFilter.all;
  _FinanceRangeFilter _financeRange = _FinanceRangeFilter.week;

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
        'rejected' => 2,
        _ => 3,
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
                  (_mergedEstablishmentData(b)['status'] as String?) ?? 'pending',
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
      _FinanceRangeFilter.week => now.subtract(const Duration(days: 7)),
      _FinanceRangeFilter.month => DateTime(now.year, now.month - 1, now.day),
      _FinanceRangeFilter.quarter => DateTime(now.year, now.month - 3, now.day),
      _FinanceRangeFilter.year => DateTime(now.year - 1, now.month, now.day),
    };
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredPayments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> payments,
  ) {
    final DateTime? cutoff = _financeCutoff();
    if (cutoff == null) {
      return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(payments);
    }

    return payments.where((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final DateTime? createdAt =
          _parseDateTime(doc.data()['createdAt']) ??
          _parseDateTime(doc.data()['createdAtClient']);
      if (createdAt == null) {
        return false;
      }
      return !createdAt.isBefore(cutoff);
    }).toList();
  }

  String _financeRangeLabel() {
    return switch (_financeRange) {
      _FinanceRangeFilter.all => 'All Time',
      _FinanceRangeFilter.week => 'Last 7 Days',
      _FinanceRangeFilter.month => 'Last 30 Days',
      _FinanceRangeFilter.quarter => 'Last 90 Days',
      _FinanceRangeFilter.year => 'Last 12 Months',
    };
  }

  String _formatSingleRateVal(dynamic val) {
    if (val is Map) {
      final String initial = (val['initial'] ?? val['hourly'] ?? '-').toString();
      final String succH = (val['succeedingHour'] ?? '').toString();
      final String succD = (val['succeedingDaily'] ?? val['daily'] ?? '').toString();
      String res = initial;
      if (succH.isNotEmpty) res += ' (+$succH/hr)';
      if (succD.isNotEmpty) res += ' ($succD/day)';
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

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _updateEstablishmentStatus(
    String establishmentId,
    String status, {
    String? rejectionReason,
  }) async {
    final Map<String, dynamic> updates = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status.toLowerCase() == 'rejected') {
      final String trimmedReason = (rejectionReason ?? '').trim();
      updates['rejectionReason'] = trimmedReason.isEmpty ? null : trimmedReason;
    } else {
      updates['rejectionReason'] = null;
    }

    await FirebaseFirestore.instance
      .collection('establishment_details')
        .doc(establishmentId)
      .set(updates, SetOptions(merge: true));
  }

  Future<void> _showEstablishmentReviewDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final Map<String, dynamic> data = _mergedEstablishmentData(doc);
    final TextEditingController rejectionReasonController =
        TextEditingController();
    final String ownerName =
        '${(data['ownerFirstName'] as String?) ?? ''} ${(data['ownerLastName'] as String?) ?? ''}'
            .trim();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Establishment Review',
            style: TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // WHO submitted this establishment.
                const Text(
                  'Registrant',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ownerName.isEmpty ? 'Unknown Owner' : ownerName,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  (data['ownerEmail'] as String?) ?? 'N/A',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Establishment Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (data['name'] as String?) ?? 'Unnamed Establishment',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  (data['address'] as String?) ?? 'No address',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  'Operating Hours: ${(data['operatingHours'] as String?) ?? 'Not provided'}',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  'Rates: ${_formatRates(data['rates'] ?? data['ratesByType'])}',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  'Slots - Car: ${(data['slotCounts']?['car'] as num?) ?? 0}, Motorcycle: ${(data['slotCounts']?['motorcycle'] as num?) ?? 0}',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                Text(
                  'Policies: ${(data['policies'] as String?) ?? 'Not provided'}',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Rejection Reason (Optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: rejectionReasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Optional note to help owner address issues before re-submission.',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            OutlinedButton(
              onPressed: () async {
                await _updateEstablishmentStatus(
                  doc.id,
                  'rejected',
                  rejectionReason: rejectionReasonController.text,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC53B3B),
              ),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _updateEstablishmentStatus(doc.id, 'approved');
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF22252C),
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
  }

  int _sameDayRevenueCount(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    double total = 0;

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, dynamic> data = doc.data();
      final DateTime? createdAt =
          _parseDateTime(data['createdAt']) ??
          _parseDateTime(data['createdAtClient']);
      final num amount = (data['amount'] as num?) ?? 0;
      if (createdAt == null) {
        continue;
      }

      final DateTime date = createdAt;
      if (date.year == day.year &&
          date.month == day.month &&
          date.day == day.day) {
        total += amount.toDouble();
      }
    }

    return total.round();
  }

  int _sameHourCount(
    int hour,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    int total = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final DateTime? createdAt =
          _parseDateTime(doc.data()['createdAt']) ??
          _parseDateTime(doc.data()['createdAtClient']);
      if (createdAt != null && createdAt.hour == hour) {
        total++;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab.index,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedTab = _AdminTab.values[index];
          });
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment_rounded),
            label: 'Facility',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments_rounded),
            label: 'Finance',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> usersSnapshot,
            ) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('establishments')
                    .snapshots(),
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                      establishmentsSnapshot,
                    ) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('establishment_details')
                            .snapshots(),
                        builder: (
                          BuildContext context,
                          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                          establishmentDetailsSnapshot,
                        ) {
                          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('payments')
                                .snapshots(),
                            builder:
                                (
                                  BuildContext context,
                                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                                  paymentsSnapshot,
                                ) {
                              if (usersSnapshot.connectionState ==
                                      ConnectionState.waiting ||
                                  establishmentsSnapshot.connectionState ==
                                      ConnectionState.waiting ||
                                  establishmentDetailsSnapshot.connectionState ==
                                      ConnectionState.waiting ||
                                  paymentsSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              users =
                                  usersSnapshot.data?.docs ??
                                  <
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >[];
                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              establishments =
                                  establishmentsSnapshot.data?.docs ??
                                  <
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >[];
                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              establishmentDetails =
                                  establishmentDetailsSnapshot.data?.docs ??
                                  <
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >[];
                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              payments =
                                  paymentsSnapshot.data?.docs ??
                                  <
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >[];

                              _establishmentDetailsById =
                                  <String, Map<String, dynamic>>{
                                    for (final QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        > doc in establishmentDetails)
                                      doc.id: doc.data(),
                                  };

                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              filteredUsers = _filteredUsers(users);

                              final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >
                              financePayments = _filteredPayments(payments);

                              final int totalUsers = users.length;
                              final int driverCount = users.where((
                                QueryDocumentSnapshot<Map<String, dynamic>> doc,
                              ) {
                                final String role =
                                    ((doc.data()['role'] as String?) ?? '')
                                        .toLowerCase();
                                return role == 'driver';
                              }).length;

                              final int parkingOwnerCount = users.where((
                                QueryDocumentSnapshot<Map<String, dynamic>> doc,
                              ) {
                                final String role =
                                    ((doc.data()['role'] as String?) ?? '')
                                        .toLowerCase();
                                return role == 'parking owner';
                              }).length;

                              final int establishmentCount =
                                  establishments.length;

                              final int pendingCount = establishments.where((
                                QueryDocumentSnapshot<Map<String, dynamic>> doc,
                              ) {
                                final String status =
                                    ((_mergedEstablishmentData(doc)['status']
                                                as String?) ??
                                            'pending')
                                        .toLowerCase();
                                return status == 'pending';
                              }).length;

                              double totalRevenue = 0;
                              for (final QueryDocumentSnapshot<
                                    Map<String, dynamic>
                                  >
                                  payment
                                  in payments) {
                                totalRevenue +=
                                    ((payment.data()['amount'] as num?) ?? 0)
                                        .toDouble();
                              }

                              final double commission = totalRevenue * 0.1;

                              double financeRevenue = 0;
                              for (final QueryDocumentSnapshot<
                                    Map<String, dynamic>
                                  >
                                  payment
                                  in financePayments) {
                                financeRevenue +=
                                    ((payment.data()['amount'] as num?) ?? 0)
                                        .toDouble();
                              }

                              final double financeCommission =
                                  financeRevenue * 0.1;

                              final DateTime now = DateTime.now();
                              final List<int> weeklyRevenue =
                                  List<int>.generate(7, (int index) {
                                    final DateTime day = DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                    ).subtract(Duration(days: 6 - index));
                                    return _sameDayRevenueCount(
                                      day,
                                      financePayments,
                                    );
                                  });

                              final List<int> peakHourCounts =
                                  List<int>.generate(8, (int index) {
                                    return _sameHourCount(
                                      index * 3,
                                      financePayments,
                                    );
                                  });

                              return ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  24,
                                ),
                                children: _buildTabContent(
                                  totalUsers: totalUsers,
                                  driverCount: driverCount,
                                  parkingOwnerCount: parkingOwnerCount,
                                  filteredUsersCount: filteredUsers.length,
                                  establishmentCount: establishmentCount,
                                  pendingCount: pendingCount,
                                  totalRevenue: totalRevenue,
                                  commission: commission,
                                  paymentCount: payments.length,
                                  weeklyRevenue: weeklyRevenue,
                                  peakHourCounts: peakHourCounts,
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
    ),
    );
  }
}
