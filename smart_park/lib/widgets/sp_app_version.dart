import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

/// A small "SmartPark v1.0.0" line at the foot of Profile and Settings, so
/// anyone reporting a problem can say which version they have.
class SpAppVersion extends StatelessWidget {
  const SpAppVersion({super.key});

  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        final String version = snapshot.data?.version ?? '';
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            version.isEmpty ? 'SmartPark' : 'SmartPark v$version',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        );
      },
    );
  }
}
