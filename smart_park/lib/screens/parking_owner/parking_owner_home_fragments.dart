part of 'package:smart_park/screens/parking_owner_home_screen.dart';

extension _ParkingOwnerHomeFragments on _ParkingOwnerHomePageState {
  InputDecoration _ownerFieldDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(
        color: Color(0xFF737A88),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(
        color: Color(0xFF9AA0AE),
        fontSize: 12,
      ),
    );
  }

  Widget _buildTabTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E2330),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF737A88),
          ),
        ),
      ],
    );
  }

  String _formatShortDate(DateTime dateTime) {
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
    final String month = months[dateTime.month - 1];
    final String day = dateTime.day.toString().padLeft(2, '0');
    return '$month $day, ${dateTime.year}';
  }

  Widget _buildBody({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required String role,
  }) {
    switch (_selectedIndex) {
      case 1:
        return _buildStaffTab(ownerId: ownerId, ownerData: ownerData);
      case 2:
        return _buildGateActivityTab(ownerId: ownerId, ownerData: ownerData);
      case 3:
        return _buildCommissionsTab(ownerId: ownerId, ownerData: ownerData);
      case 4:
        return _buildProfileTab(ownerId: ownerId, role: role);
      case 0:
      default:
        return _buildFacilityTab(ownerId: ownerId, ownerData: ownerData);
    }
  }

  Widget _buildFacilityTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    final String initialEstablishmentId = _resolveFacilityId(ownerData);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: initialEstablishmentId.isEmpty
          ? FirebaseFirestore.instance
              .collection('establishments')
              .where('ownerId', isEqualTo: ownerId)
              .limit(1)
              .snapshots()
          : null,
      builder: (context, estSnapshot) {
        String establishmentId = initialEstablishmentId;
        if (establishmentId.isEmpty &&
            estSnapshot.hasData &&
            estSnapshot.data!.docs.isNotEmpty) {
          establishmentId = estSnapshot.data!.docs.first.id;
        }
        final bool hasRegisteredFacility = establishmentId.isNotEmpty;

        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            _buildTabTitle(
              'Facility',
              'Register and manage your parking establishment details.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0x35FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFF2F3544),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasRegisteredFacility
                          ? 'Facility linked to your account'
                          : 'No facility registered yet',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2532),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _OwnerSectionCard(
              title: 'Facility Setup',
              subtitle: hasRegisteredFacility
                  ? 'Your establishment ID is shown below.'
                  : 'Create your establishment to start onboarding staff.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E7EF)),
                    ),
                    child: Text(
                      hasRegisteredFacility
                          ? 'Facility ID: $establishmentId'
                          : 'Facility ID: Not available yet',
                      style: const TextStyle(
                        color: Color(0xFF596173),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openFacilityDialog(
                        ownerId: ownerId,
                        ownerData: ownerData,
                      ),
                      icon: Icon(
                        hasRegisteredFacility
                            ? Icons.edit_rounded
                            : Icons.add_business_rounded,
                      ),
                      label: Text(
                        hasRegisteredFacility
                            ? 'Update Facility'
                            : 'Register Facility',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: const Color(0xFF22252C),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGateActivityTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    final String initialFacilityId = _resolveFacilityId(ownerData);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: initialFacilityId.isEmpty
          ? FirebaseFirestore.instance
              .collection('establishments')
              .where('ownerId', isEqualTo: ownerId)
              .limit(1)
              .snapshots()
          : null,
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> estSnapshot) {
        String facilityId = initialFacilityId;
        if (facilityId.isEmpty &&
            estSnapshot.hasData &&
            estSnapshot.data!.docs.isNotEmpty) {
          facilityId = estSnapshot.data!.docs.first.id;
        }
        if (facilityId.isEmpty) {
          return ListView(
            padding: const EdgeInsets.only(top: 8),
            children: const <Widget>[
              _OwnerSectionCard(
                title: 'No Facility Linked',
                subtitle: 'Register a facility to see gate activity.',
                child: SizedBox.shrink(),
              ),
            ],
          );
        }
        return _GateActivityContent(facilityId: facilityId);
      },
    );
  }

  Widget _buildStaffTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    final String initialFacilityId = _resolveFacilityId(ownerData);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: initialFacilityId.isEmpty
          ? FirebaseFirestore.instance
              .collection('establishments')
              .where('ownerId', isEqualTo: ownerId)
              .limit(1)
              .snapshots()
          : null,
      builder: (context, estSnapshot) {
        String facilityId = initialFacilityId;
        if (facilityId.isEmpty &&
            estSnapshot.hasData &&
            estSnapshot.data!.docs.isNotEmpty) {
          facilityId = estSnapshot.data!.docs.first.id;
        }
        final bool hasFacilityId = facilityId.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        _buildTabTitle(
          'Staff',
          'Create and manage staff accounts linked to your facility.',
        ),
        const SizedBox(height: 14),
        _OwnerSectionCard(
          title: 'Add Staff Member',
          subtitle: hasFacilityId
              ? 'Enter a name - a login username and password are generated automatically.'
              : 'Register your facility first to enable staff onboarding.',
          child: Form(
            key: _staffFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _staffNameController,
                  enabled: hasFacilityId,
                  decoration: _ownerFieldDecoration(
                    label: 'Staff Name',
                    hint: 'Juan Dela Cruz',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (value) {
                    final String text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: !hasFacilityId || _addingStaff
                        ? null
                        : () => _addStaff(ownerId: ownerId, facilityId: facilityId),
                    icon: _addingStaff
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_addingStaff ? 'Adding Staff...' : 'Add Staff'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: const Color(0xFF22252C),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _OwnerSectionCard(
          title: 'Active Staff',
          subtitle: 'Accounts currently assigned under this owner.',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('staff_accounts')
                .where('ownerId', isEqualTo: ownerId)
                .snapshots(),
            builder: (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
            ) {
              if (snapshot.hasError) {
                return const Text(
                  'Unable to load staff records right now.',
                  style: TextStyle(color: Color(0xFF737A88)),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<QueryDocumentSnapshot<Map<String, dynamic>>> staffDocs =
                  snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              if (staffDocs.isEmpty) {
                return const Text(
                  'No staff accounts yet. Add your first staff member above.',
                  style: TextStyle(
                    color: Color(0xFF737A88),
                    fontWeight: FontWeight.w500,
                  ),
                );
              }

              return Column(
                children: staffDocs.map((
                  QueryDocumentSnapshot<Map<String, dynamic>> doc,
                ) {
                  final Map<String, dynamic> data = doc.data();
                  final String rawName = (data['name'] as String?)?.trim() ?? '';
                  final String name =
                      rawName.isEmpty ? 'Unnamed Staff' : rawName;
                  final String username =
                      (data['username'] as String?)?.trim() ?? 'No username';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E7EF)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2CA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.badge_rounded,
                            size: 18,
                            color: Color(0xFF3D4352),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Color(0xFF1E2330),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                username,
                                style: const TextStyle(
                                  color: Color(0xFF737A88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _removeStaff(doc.id),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFB14141),
                          ),
                          tooltip: 'Remove staff',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _buildCommissionsTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    final String initialFacilityId = _resolveFacilityId(ownerData);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: initialFacilityId.isEmpty
          ? FirebaseFirestore.instance
              .collection('establishments')
              .where('ownerId', isEqualTo: ownerId)
              .limit(1)
              .snapshots()
          : null,
      builder: (
        BuildContext context,
        AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> estSnapshot,
      ) {
        String facilityId = initialFacilityId;
        if (facilityId.isEmpty &&
            estSnapshot.hasData &&
            estSnapshot.data!.docs.isNotEmpty) {
          facilityId = estSnapshot.data!.docs.first.id;
        }

        if (facilityId.isEmpty &&
            initialFacilityId.isEmpty &&
            estSnapshot.connectionState == ConnectionState.waiting) {
          return ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              _buildTabTitle(
                'Commissions',
                'Track transaction commissions and payout progress.',
              ),
              const SizedBox(height: 14),
              const _OwnerSectionCard(
                title: 'Commissions',
                subtitle: 'Loading facility information...',
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            _buildTabTitle(
              'Commissions',
              'Track transaction commissions and payout progress.',
            ),
            const SizedBox(height: 14),
            if (facilityId.isEmpty)
              const _OwnerSectionCard(
                title: 'No Facility Linked',
                subtitle:
                    'Register your facility first so commission records can be tracked here.',
                child: SizedBox.shrink(),
              )
            else
              _CommissionsListContent(
                facilityId: facilityId,
                ownerId: ownerId,
                formatShortDate: _formatShortDate,
              ),
          ],
        );
      },
    );
  }

  Widget _buildProfileTab({
    required String ownerId,
    required String role,
  }) {
    final String firstName = _profileFirstNameController.text.trim();
    final String lastName = _profileLastNameController.text.trim();
    final String displayName = '$firstName $lastName'.trim().isEmpty
        ? 'Parking Owner'
        : '$firstName $lastName'.trim();

    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        _buildTabTitle(
          'Profile',
          'Maintain your account details and session settings.',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0x35FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 30,
                  color: Color(0xFF313645),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C2230),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _profileEmailController.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4C5362),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OwnerSectionCard(
          title: 'Account Information',
          subtitle: 'Update your personal details used across the platform.',
          child: Column(
            children: [
              TextFormField(
                controller: _profileFirstNameController,
                decoration: _ownerFieldDecoration(
                  label: 'First Name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _profileLastNameController,
                decoration: _ownerFieldDecoration(
                  label: 'Last Name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _profileEmailController,
                decoration: _ownerFieldDecoration(
                  label: 'Email',
                  icon: Icons.alternate_email_rounded,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _savingProfile ? null : () => _saveProfile(ownerId, role),
                  icon: _savingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _savingProfile ? 'Saving Profile...' : 'Save Changes',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: const Color(0xFF22252C),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: const Color(0xFFAF2E2E),
                    side: const BorderSide(color: Color(0xFFF0C9C9)),
                    backgroundColor: const Color(0xFFFFF6F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnerSectionCard extends StatelessWidget {
  const _OwnerSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E2330),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF737A88),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _OwnerMetricTile extends StatelessWidget {
  const _OwnerMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF737A88),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E2330),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

class _CommissionRecord {
  const _CommissionRecord({
    required this.id,
    required this.driverName,
    required this.grossAmount,
    required this.platformFee,
    required this.netToOwner,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String driverName;
  final double grossAmount;
  final double platformFee;
  final double netToOwner;
  final String status;
  final DateTime? createdAt;
}

class _CommissionsListContent extends StatelessWidget {
  const _CommissionsListContent({
    required this.facilityId,
    required this.ownerId,
    required this.formatShortDate,
  });

  final String facilityId;
  final String ownerId;
  final String Function(DateTime) formatShortDate;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> txSnapshot,
      ) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('payment_splits')
              .snapshots(),
          builder: (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> splitSnapshot,
          ) {
            if (txSnapshot.hasError && splitSnapshot.hasError) {
              return const _OwnerSectionCard(
                title: 'Commissions',
                subtitle: 'Unable to load commission records right now.',
                child: SizedBox.shrink(),
              );
            }

            if (txSnapshot.connectionState == ConnectionState.waiting &&
                splitSnapshot.connectionState == ConnectionState.waiting) {
              return const _OwnerSectionCard(
                title: 'Commissions',
                subtitle: 'Loading commission records...',
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final List<QueryDocumentSnapshot<Map<String, dynamic>>> txDocs =
                txSnapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> splitDocs =
                splitSnapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            final Map<String, Map<String, dynamic>> splitByTxId =
                <String, Map<String, dynamic>>{};
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in splitDocs) {
              final Map<String, dynamic> data = doc.data();
              final String estId = ((data['establishmentId'] as String?) ??
                      (data['establishmentID'] as String?) ??
                      '')
                  .trim();
              final String destAcc =
                  ((data['destinationAccountId'] as String?) ?? '').trim();

              if (estId == facilityId ||
                  (facilityId.isNotEmpty && estId == facilityId) ||
                  (ownerId.isNotEmpty && destAcc == ownerId)) {
                final String txId =
                    ((data['transactionId'] as String?) ?? doc.id).trim();
                if (txId.isNotEmpty) {
                  splitByTxId[txId] = data;
                }
              }
            }

            final Map<String, _CommissionRecord> recordMap =
                <String, _CommissionRecord>{};

            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in txDocs) {
              final Map<String, dynamic> data = doc.data();
              final String txEstId = ((data['establishmentId'] as String?) ??
                      (data['establishmentID'] as String?) ??
                      '')
                  .trim();
              final String txOwnerId =
                  ((data['ownerId'] as String?) ?? '').trim();

              final bool matchesFacility = (txEstId == facilityId) ||
                  (facilityId.isNotEmpty && txEstId == facilityId) ||
                  (ownerId.isNotEmpty && txOwnerId == ownerId);

              if (!matchesFacility) {
                continue;
              }

              final String txId = doc.id;
              final Map<String, dynamic>? matchingSplit = splitByTxId[txId];

              double grossAmount = 0;
              double platformFee = 0;
              double netToOwner = 0;
              String status = ((data['status'] as String?) ??
                      (data['paymentStatus'] as String?) ??
                      'paid')
                  .toUpperCase();
              DateTime? createdAt = _parseDateTime(data['createdAt']) ??
                  _parseDateTime(data['createdAtClient']);
              String driverName =
                  ((data['driverName'] as String?) ?? '').trim();
              if (driverName.isEmpty) {
                driverName =
                    ((data['driverEmail'] as String?) ?? 'Driver').trim();
              }

              if (matchingSplit != null) {
                grossAmount =
                    ((matchingSplit['grossAmountCentavos'] as num?) ?? 0) / 100;
                platformFee =
                    ((matchingSplit['platformFeeCentavos'] as num?) ?? 0) / 100;
                netToOwner =
                    ((matchingSplit['netToOwnerCentavos'] as num?) ?? 0) / 100;
                if (matchingSplit['status'] != null) {
                  status =
                      (matchingSplit['status'] as String).toUpperCase();
                }
                if (matchingSplit['createdAt'] != null) {
                  createdAt = _parseDateTime(matchingSplit['createdAt']);
                }
              } else {
                final double amount =
                    ((data['amount'] as num?) ?? 0).toDouble();
                final int grossCentavos =
                    ((data['grossAmountCentavos'] as num?) ?? (amount * 100))
                        .round();
                final int feeCentavos =
                    ((data['platformFeeCentavos'] as num?) ??
                            (grossCentavos * 0.05))
                        .round();
                final int processorCentavos =
                    ((data['estimatedProcessorFeeCentavos'] as num?) ??
                            (grossCentavos * 0.02))
                        .round();
                final int netCentavos =
                    grossCentavos - feeCentavos - processorCentavos;

                grossAmount = grossCentavos / 100;
                platformFee = feeCentavos / 100;
                netToOwner = netCentavos / 100;
              }

              recordMap[txId] = _CommissionRecord(
                id: txId,
                driverName: driverName,
                grossAmount: grossAmount,
                platformFee: platformFee,
                netToOwner: netToOwner,
                status: status,
                createdAt: createdAt,
              );
            }

            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in splitDocs) {
              final Map<String, dynamic> data = doc.data();
              final String estId = ((data['establishmentId'] as String?) ??
                      (data['establishmentID'] as String?) ??
                      '')
                  .trim();
              final String destAcc =
                  ((data['destinationAccountId'] as String?) ?? '').trim();
              final bool matchesFacility = (estId == facilityId) ||
                  (facilityId.isNotEmpty && estId == facilityId) ||
                  (ownerId.isNotEmpty && destAcc == ownerId);

              if (!matchesFacility) {
                continue;
              }

              final String txId =
                  ((data['transactionId'] as String?) ?? doc.id).trim();
              if (!recordMap.containsKey(txId)) {
                final double grossAmount =
                    ((data['grossAmountCentavos'] as num?) ?? 0) / 100;
                final double platformFee =
                    ((data['platformFeeCentavos'] as num?) ?? 0) / 100;
                final double netToOwner =
                    ((data['netToOwnerCentavos'] as num?) ?? 0) / 100;
                final String status =
                    ((data['status'] as String?) ?? 'paid').toUpperCase();
                final DateTime? createdAt = _parseDateTime(data['createdAt']);

                recordMap[txId] = _CommissionRecord(
                  id: txId,
                  driverName: 'Driver',
                  grossAmount: grossAmount,
                  platformFee: platformFee,
                  netToOwner: netToOwner,
                  status: status,
                  createdAt: createdAt,
                );
              }
            }

            final List<_CommissionRecord> records = recordMap.values.toList();
            records.sort((_CommissionRecord a, _CommissionRecord b) {
              final DateTime aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final DateTime bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

            double totalRevenue = 0;
            double totalCommission = 0;

            for (final _CommissionRecord record in records) {
              totalRevenue += record.grossAmount;
              totalCommission += record.platformFee;
            }

            return Column(
              children: [
                _OwnerSectionCard(
                  title: 'Commission Summary',
                  subtitle: '${records.length} transaction(s) recorded',
                  child: Row(
                    children: [
                      Expanded(
                        child: _OwnerMetricTile(
                          label: 'Revenue',
                          value: 'PHP ${totalRevenue.toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _OwnerMetricTile(
                          label: 'Commission',
                          value:
                              'PHP ${totalCommission.toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _OwnerSectionCard(
                  title: 'Recent Transactions',
                  subtitle: 'Latest parking transactions for this facility.',
                  child: records.isEmpty
                      ? const Text(
                          'No commission records yet.',
                          style: TextStyle(
                            color: Color(0xFF737A88),
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Column(
                          children: records.take(12).map((
                            _CommissionRecord record,
                          ) {
                            final String dateText = record.createdAt == null
                                ? 'Date unavailable'
                                : formatShortDate(record.createdAt!);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE4E7EF),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'PHP ${record.grossAmount.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Color(0xFF1E2330),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (record.driverName.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  '· ${record.driverName}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF737A88),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Commission: PHP ${record.platformFee.toStringAsFixed(2)} · Payout: PHP ${record.netToOwner.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Color(0xFF737A88),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateText,
                                          style: const TextStyle(
                                            color: Color(0xFF737A88),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: record.status == 'PAID'
                                          ? const Color(0xFFE8F6EF)
                                          : const Color(0xFFFFF3D9),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      record.status,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: record.status == 'PAID'
                                            ? const Color(0xFF1F7A4A)
                                            : const Color(0xFF946200),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _GateActivityContent extends StatelessWidget {
  const _GateActivityContent({required this.facilityId});

  final String facilityId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('activity_logs')
          .where('establishmentID', isEqualTo: facilityId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        int cashDueCount = 0;
        double cashDueTotal = 0;
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
          final Map<String, dynamic> data = doc.data();
          final String oStatus =
              ((data['overtimeStatus'] as String?) ?? '').toLowerCase();
          if (oStatus == 'cash_due') {
            cashDueCount++;
            cashDueTotal += ((data['overtimeAmount'] as num?) ?? 0).toDouble();
          }
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: <Widget>[
            const Text(
              'Gate Activity',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('Same entry/exit trail staff sees, incl. overtime.'),
            const SizedBox(height: 14),
            _OwnerSectionCard(
              title: 'Cash still to collect',
              subtitle: 'Overtime flagged at exit.',
              child: Row(
                children: <Widget>[
                  _OwnerMetricTile(
                    label: 'Open items',
                    value: cashDueCount.toString(),
                  ),
                  const SizedBox(width: 10),
                  _OwnerMetricTile(
                    label: 'Cash total',
                    value: 'PHP ${cashDueTotal.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _OwnerSectionCard(
              title: 'Latest scans',
              subtitle: 'Newest first, up to 100.',
              child: Builder(
                builder: (BuildContext context) {
                  if (snapshot.hasError) {
                    return const Text('Unable to load activity.');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (docs.isEmpty) {
                    return const Text('No entry/exit scans yet.');
                  }
                  return Column(
                    children: docs.map((
                      QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    ) {
                      final Map<String, dynamic> data = doc.data();
                      final String plate =
                          (data['vehiclePlate'] as String?) ?? 'N/A';
                      final String scanType =
                          ((data['scanType'] as String?) ?? 'entry')
                              .toUpperCase();
                      final String status =
                          ((data['status'] as String?) ?? '?').toUpperCase();
                      final int overtimeHours =
                          ((data['overtimeHours'] as num?) ?? 0).toInt();
                      final double overtimeAmount =
                          ((data['overtimeAmount'] as num?) ?? 0).toDouble();
                      final String reason =
                          (data['decisionReason'] as String?) ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE4E7EF),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '$plate - $scanType',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  status,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            if (overtimeHours > 0)
                              Text(
                                'Overtime ${overtimeHours}h / PHP '
                                '${overtimeAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (reason.isNotEmpty)
                              Text(
                                reason,
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
