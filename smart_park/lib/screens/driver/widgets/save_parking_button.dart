import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../theme/app_theme.dart';
import '../services/driver_favorites.dart';

/// Heart that saves or un-saves a facility for the signed-in driver.
class DriverSaveParkingButton extends StatelessWidget {
  const DriverSaveParkingButton({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || establishmentId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<Set<String>>(
      stream: DriverFavorites.watch(uid),
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snapshot) {
        final bool saved = snapshot.data?.contains(establishmentId) ?? false;
        return IconButton(
          tooltip: saved ? 'Remove from saved parking' : 'Save this parking',
          icon: Icon(
            saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: saved ? AppTheme.danger : AppTheme.textDark,
          ),
          onPressed: !snapshot.hasData
              ? null
              : () async {
                  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                    context,
                  );
                  try {
                    await DriverFavorites.setSaved(
                      uid,
                      establishmentId,
                      saved: !saved,
                    );
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            saved
                                ? 'Removed from your parking.'
                                : 'Saved to your parking.',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  } catch (error, stack) {
                    reportError(error, stack, reason: 'Save parking');
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not update. Please try again.'),
                      ),
                    );
                  }
                },
        );
      },
    );
  }
}
