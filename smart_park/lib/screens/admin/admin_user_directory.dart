// ignore_for_file: invalid_use_of_protected_member

part of 'admin_home_page.dart';

/// Users tab: directory rows and the user details dialog.
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

  Widget _buildUserDirectory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDirectoryState) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> sortedUsers =
            _filteredUsers(users);

        return SpSectionCard(
          icon: Icons.people_alt_outlined,
          title: 'User Directory',
          subtitle: 'Drivers and parking owners.',
          trailing: SpChip(label: '${sortedUsers.length}', color: spExitColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _usersSearchController,
                onChanged: (String value) {
                  setDirectoryState(() {
                    _usersSearchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or role',
                  prefixIcon: const Icon(Icons.search_rounded),
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
                options: const <(_UserRoleFilter, String)>[
                  (_UserRoleFilter.all, 'All'),
                  (_UserRoleFilter.driver, 'Drivers'),
                  (_UserRoleFilter.parkingOwner, 'Owners'),
                ],
                selected: _userRoleFilter,
                onChanged: (_UserRoleFilter filter) =>
                    setDirectoryState(() => _userRoleFilter = filter),
              ),
              const SizedBox(height: 12),
              if (sortedUsers.isEmpty)
                const SpEmptyState(
                  boxed: false,
                  icon: Icons.person_search_rounded,
                  message: 'No users match this search.',
                )
              else if (_isTablet)
                SpGrid(
                  spacing: 10,
                  children: sortedUsers.map(_buildUserRow).toList(),
                )
              else
                ...sortedUsers.map(_buildUserRow),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    final String fullName =
        '${(data['firstName'] as String?)?.trim() ?? ''} ${(data['lastName'] as String?)?.trim() ?? ''}'
            .trim();
    final String email = ((data['email'] as String?) ?? '').trim();
    final bool isOwner =
        _normalize((data['role'] as String?) ?? '') == 'parking owner';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showUserDetailsDialog(doc),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.3),
                  child: Text(
                    _initials(fullName.isEmpty ? '?' : fullName),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
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
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SpChip(
                  label: isOwner ? 'Owner' : 'Driver',
                  color: isOwner ? spEntryColor : spExitColor,
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showUserDetailsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final Map<String, dynamic> data = doc.data();
    final String firstName = (data['firstName'] as String?)?.trim() ?? '';
    final String lastName = (data['lastName'] as String?)?.trim() ?? '';
    final String fullName = '$firstName $lastName'.trim();
    final String email = _readText(data['email'], fallback: 'Not provided');
    final String rawRole = (data['role'] as String?)?.trim() ?? 'Unassigned';
    final String role = rawRole.toLowerCase() == 'parking owner'
        ? 'Parking Owner'
        : (rawRole.toLowerCase() == 'driver' ? 'Driver' : rawRole);
    final String phone =
        (data['phoneNumber'] ?? data['contactNumber'] ?? data['phone'])
            ?.toString()
            .trim() ??
        '';
    final DateTime? createdAt =
        _parseDateTime(data['createdAt']) ??
        _parseDateTime(data['createdAtClient']);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: AppTheme.textDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'User Details',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUserDetailRow(
                  icon: Icons.badge_outlined,
                  label: 'Full Name',
                  value: fullName.isEmpty ? 'Unnamed User' : fullName,
                ),
                const SizedBox(height: 10),
                _buildUserDetailRow(
                  icon: Icons.work_outline_rounded,
                  label: 'Role',
                  value: role,
                ),
                const SizedBox(height: 10),
                _buildUserDetailRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildUserDetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone Number',
                    value: phone,
                  ),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 10),
                  _buildUserDetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Joined',
                    value:
                        '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
        ],
      ),
    );
  }
}
