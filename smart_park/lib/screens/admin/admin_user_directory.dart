// ignore_for_file: invalid_use_of_protected_member

part of 'admin_home_page.dart';

/// Users tab: a compact, paged directory and the user details sheet.
extension _AdminUserDirectory on _AdminHomePageState {
  String _initials(String name) {
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _userFullName(Map<String, dynamic> data) =>
      '${(data['firstName'] as String?)?.trim() ?? ''} '
              '${(data['lastName'] as String?)?.trim() ?? ''}'
          .trim();

  bool _isOwnerData(Map<String, dynamic> data) =>
      _normalize((data['role'] as String?) ?? '') == 'parking owner';

  /// Owners are green and drivers blue, here and in the details sheet.
  Color _roleColor(bool owner) => owner ? spEntryColor : spExitColor;

  Widget _userAvatar(String name, bool owner, {double radius = 20}) {
    final Color color = _roleColor(owner);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        _initials(name.isEmpty ? '?' : name),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.75,
          color: color,
        ),
      ),
    );
  }

  /// The owner's facility, matched by ownerId, if they registered one.
  QueryDocumentSnapshot<Map<String, dynamic>>? _facilityOf(
    String ownerId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in establishments) {
      if ((doc.data()['ownerId'] as String?) == ownerId) return doc;
    }
    return null;
  }

  Widget _buildUserDirectory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDirectoryState) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> matches =
            _filteredUsers(users);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> shown = matches
            .take(_usersShown)
            .toList();
        final int remaining = matches.length - shown.length;

        // Any change to what is listed starts again from the first page.
        void update(VoidCallback change) => setDirectoryState(() {
          change();
          _usersShown = _kUsersPage;
        });

        int countOf(String role) => users
            .where(
              (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                  _normalize((d.data()['role'] as String?) ?? '') == role,
            )
            .length;
        final int drivers = countOf('driver');
        final int owners = countOf('parking owner');

        final List<Widget> rows = <Widget>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in shown)
            _buildUserRow(doc, establishments),
        ];

        return SpSectionCard(
          icon: Icons.people_alt_outlined,
          title: 'User Directory',
          subtitle: 'Drivers and parking owners. Tap one for details.',
          trailing: SpChip(label: '${matches.length}', color: spExitColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _usersSearchController,
                onChanged: (String value) =>
                    update(() => _usersSearchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or role',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _usersSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => update(() {
                            _usersSearchController.clear();
                            _usersSearchQuery = '';
                          }),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SpSegmentedControl<_UserRoleFilter>(
                options: <(_UserRoleFilter, String)>[
                  (_UserRoleFilter.all, 'All · ${drivers + owners}'),
                  (_UserRoleFilter.driver, 'Drivers · $drivers'),
                  (_UserRoleFilter.parkingOwner, 'Owners · $owners'),
                ],
                selected: _userRoleFilter,
                onChanged: (_UserRoleFilter filter) =>
                    update(() => _userRoleFilter = filter),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      matches.isEmpty
                          ? 'No matches'
                          : 'Showing ${shown.length} of ${matches.length}',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                  PopupMenuButton<_UserSortOption>(
                    tooltip: 'Sort users',
                    initialValue: _userSort,
                    onSelected: (_UserSortOption sort) =>
                        update(() => _userSort = sort),
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<_UserSortOption>>[
                          PopupMenuItem<_UserSortOption>(
                            value: _UserSortOption.newest,
                            child: Text('Newest first'),
                          ),
                          PopupMenuItem<_UserSortOption>(
                            value: _UserSortOption.name,
                            child: Text('Name, A to Z'),
                          ),
                        ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sort_rounded,
                            size: 18,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _userSort == _UserSortOption.newest
                                ? 'Newest first'
                                : 'Name, A to Z',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (matches.isEmpty)
                const SpEmptyState(
                  boxed: false,
                  icon: Icons.person_search_rounded,
                  message: 'No users match this search.',
                )
              else if (_isTablet)
                SpGrid(spacing: 10, equalHeight: true, children: rows)
              else
                // One bordered panel with dividers, like the facility list,
                // so long lists stay compact.
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: AppTheme.surfaceAlt,
                          ),
                        rows[i],
                      ],
                    ],
                  ),
                ),
              if (remaining > 0) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      setDirectoryState(() => _usersShown += _kUsersPage),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    'Show ${remaining < _kUsersPage ? remaining : _kUsersPage} '
                    'more · $remaining left',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textDark,
                    side: BorderSide(color: AppTheme.border),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String fullName = _userFullName(data);
    final String email = ((data['email'] as String?) ?? '').trim();
    final bool isOwner = _isOwnerData(data);
    final QueryDocumentSnapshot<Map<String, dynamic>>? facility = isOwner
        ? _facilityOf(doc.id, establishments)
        : null;
    final String facilityName = facility == null
        ? ''
        : ((_mergedEstablishmentData(facility)['name'] as String?) ?? '')
              .trim();
    final DateTime? joined = _userJoinedAt(data);

    final Widget row = InkWell(
      onTap: () => _showUserDetailsSheet(doc, establishments),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            _userAvatar(fullName, isOwner, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName.isEmpty ? 'Unnamed User' : fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    email.isEmpty ? 'No email' : email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  if (facilityName.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            facilityName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SpChip(
                  label: isOwner ? 'Owner' : 'Driver',
                  color: _roleColor(isOwner),
                ),
                if (joined != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(joined),
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );

    if (!_isTablet) return row;
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: row,
    );
  }

  Future<int> _countWhere(String collection, String field, String value) async {
    final AggregateQuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where(field, isEqualTo: value)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  Future<void> _showUserDetailsSheet(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) async {
    final Map<String, dynamic> data = doc.data();
    final String fullName = _userFullName(data);
    final String email = ((data['email'] as String?) ?? '').trim();
    final bool isOwner = _isOwnerData(data);
    final String phone =
        (data['phoneNumber'] ?? data['contactNumber'] ?? data['phone'])
            ?.toString()
            .trim() ??
        '';
    final DateTime? joined = _userJoinedAt(data);
    final String termsVersion = ((data['termsVersion'] ?? '') as Object)
        .toString()
        .trim();
    final DateTime? termsAt = _parseDateTime(data['termsAcceptedAt']);
    final QueryDocumentSnapshot<Map<String, dynamic>>? facility = isOwner
        ? _facilityOf(doc.id, establishments)
        : null;

    // Counts only: the admin sees how active an account is, not its money.
    final Future<List<int>> activity = isOwner
        ? Future.wait(<Future<int>>[
            _countWhere('staff_accounts', 'ownerId', doc.id),
          ])
        : Future.wait(<Future<int>>[
            _countWhere('payments', 'driverId', doc.id),
            _countWhere('driver_reports', 'driverId', doc.id),
            _countWhere('driver_warnings', 'driverId', doc.id),
          ]);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      // Phone-width and centered on tablets.
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(
                children: [
                  _userAvatar(fullName, isOwner, radius: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'Unnamed User' : fullName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SpChip(
                              label: isOwner ? 'Parking Owner' : 'Driver',
                              color: _roleColor(isOwner),
                            ),
                            if (joined != null)
                              Text(
                                'Joined ${spFormatDate(joined)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _sheetLabel('Contact'),
              _detailTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: email.isEmpty ? 'Not provided' : email,
                copyValue: email,
              ),
              if (phone.isNotEmpty)
                _detailTile(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: phone,
                  copyValue: phone,
                ),
              const SizedBox(height: 16),
              if (isOwner) ...[
                _sheetLabel('Facility'),
                _ownerFacilityTile(facility),
                const SizedBox(height: 10),
              ] else
                _sheetLabel('Activity'),
              FutureBuilder<List<int>>(
                future: activity,
                builder:
                    (BuildContext context, AsyncSnapshot<List<int>> snapshot) {
                      String n(int i) => snapshot.hasError
                          ? '-'
                          : snapshot.hasData
                          ? '${snapshot.data![i]}'
                          : '…';
                      if (isOwner) {
                        return _detailTile(
                          icon: Icons.badge_outlined,
                          label: 'Staff accounts',
                          value: n(0),
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: _miniStat(
                              Icons.confirmation_number_outlined,
                              'Paid tickets',
                              n(0),
                              spEntryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _miniStat(
                              Icons.flag_outlined,
                              'Reports',
                              n(1),
                              spInsideColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _miniStat(
                              Icons.warning_amber_rounded,
                              'Warnings',
                              n(2),
                              spDeniedColor,
                            ),
                          ),
                        ],
                      );
                    },
              ),
              const SizedBox(height: 16),
              _sheetLabel('Account'),
              _detailTile(
                icon: Icons.gavel_rounded,
                label: 'Terms and Privacy',
                value: termsAt == null
                    ? 'No acceptance on record'
                    : 'Accepted ${spFormatDate(termsAt)}'
                          '${termsVersion.isEmpty ? '' : ' · version $termsVersion'}',
              ),
              _detailTile(
                icon: Icons.fingerprint_rounded,
                label: 'User ID',
                value: doc.id,
                copyValue: doc.id,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w800,
        color: AppTheme.textMuted,
      ),
    ),
  );

  /// One fact about the user, with a copy button when [copyValue] is set.
  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
    String copyValue = '',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          if (copyValue.isNotEmpty)
            IconButton(
              tooltip: 'Copy $label',
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppTheme.textMuted,
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: copyValue));
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$label copied.')));
              },
            ),
        ],
      ),
    );
  }

  /// The owner's facility with its review status, or a note that they have
  /// not registered one.
  Widget _ownerFacilityTile(
    QueryDocumentSnapshot<Map<String, dynamic>>? facility,
  ) {
    if (facility == null) {
      return _detailTile(
        icon: Icons.storefront_outlined,
        label: 'Facility',
        value: 'Not registered yet',
      );
    }
    final Map<String, dynamic> data = _mergedEstablishmentData(facility);
    final String name = _readText(data['name'], fallback: 'Unnamed facility');
    final String address = _readText(data['address'], fallback: '');
    final String status = ((data['status'] as String?) ?? 'pending')
        .toLowerCase();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: spEntryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(Icons.storefront_rounded, color: spEntryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildReviewStatusChip(
                    status,
                    resubmitted:
                        status == 'pending' && data['resubmittedAt'] != null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
