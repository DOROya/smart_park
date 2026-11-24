import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/gate_scan_service.dart' show isStaffRecordActive;
import '../../theme/app_theme.dart';
import '../../widgets/sp_loading.dart';
import '../auth/sign_in_screen.dart';
import '../parking_owner/parking_owner_home_screen.dart';

/// A supervisor's home: their facility's owner screens without the
/// owner-only parts, from their staff record (`staff_accounts/{uid}` with
/// role "supervisor").
class SupervisorHomePage extends StatelessWidget {
  const SupervisorHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '-';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('staff_accounts')
          .doc(uid)
          .snapshots(),
      builder: (BuildContext context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SpLoadingScreen();
        }
        final Map<String, dynamic>? record = snapshot.data?.data();
        final String facilityId = ((record?['facilityId'] as String?) ?? '')
            .trim();
        final String ownerId = ((record?['ownerId'] as String?) ?? '').trim();
        if (record == null ||
            record['role'] != 'supervisor' ||
            !isStaffRecordActive(record) ||
            facilityId.isEmpty ||
            ownerId.isEmpty) {
          return const _NotActive();
        }
        return ParkingOwnerHomePage(
          key: ValueKey<String>('supervisor_$facilityId'),
          role: 'supervisor',
          supervisor: SupervisorScope(
            facilityId: facilityId,
            ownerId: ownerId,
            name: ((record['name'] as String?) ?? '').trim(),
          ),
        );
      },
    );
  }
}

class _NotActive extends StatelessWidget {
  const _NotActive();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'This supervisor account is not active.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask the facility owner to check your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  final NavigatorState navigator = Navigator.of(context);
                  await FirebaseAuth.instance.signOut();
                  await navigator.pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignInScreen(),
                    ),
                    (Route<dynamic> route) => false,
                  );
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
