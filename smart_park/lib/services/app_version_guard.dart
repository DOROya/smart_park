import 'package:package_info_plus/package_info_plus.dart';

class AppVersionCheckResult {
  const AppVersionCheckResult({
    required this.enabled,
    required this.isOutdated,
    required this.currentVersion,
    required this.requiredVersion,
    required this.message,
  });

  final bool enabled;
  final bool isOutdated;
  final String currentVersion;
  final String requiredVersion;
  final String message;
}

class AppVersionGuard {
  // Configure this at run/build time for development checks.
  // Example: --dart-define LATEST_DEV_VERSION=1.0.0+12
  static const String _latestDevVersion = String.fromEnvironment(
    'LATEST_DEV_VERSION',
    defaultValue: '',
  );

  static Future<AppVersionCheckResult> check() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String currentVersion =
        '${packageInfo.version}+${packageInfo.buildNumber}';

    final String requiredVersion = _latestDevVersion.trim();
    if (requiredVersion.isEmpty) {
      return AppVersionCheckResult(
        enabled: false,
        isOutdated: false,
        currentVersion: currentVersion,
        requiredVersion: '',
        message: 'Version check disabled (LATEST_DEV_VERSION is not set).',
      );
    }

    final int comparison = _compareVersion(currentVersion, requiredVersion);
    final bool isOutdated = comparison < 0;
    return AppVersionCheckResult(
      enabled: true,
      isOutdated: isOutdated,
      currentVersion: currentVersion,
      requiredVersion: requiredVersion,
      message: isOutdated
          ? 'Installed app is older than expected for this dev run.'
          : 'Installed app version is up to date for this dev run.',
    );
  }

  static int _compareVersion(String left, String right) {
    final _VersionParts a = _VersionParts.parse(left);
    final _VersionParts b = _VersionParts.parse(right);

    if (a.major != b.major) {
      return a.major.compareTo(b.major);
    }
    if (a.minor != b.minor) {
      return a.minor.compareTo(b.minor);
    }
    if (a.patch != b.patch) {
      return a.patch.compareTo(b.patch);
    }
    return a.build.compareTo(b.build);
  }
}

class _VersionParts {
  const _VersionParts({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static _VersionParts parse(String input) {
    final List<String> plusParts = input.trim().split('+');
    final String semverPart = plusParts.isNotEmpty ? plusParts.first : '0.0.0';

    final List<String> semverParts = semverPart.split('.');
    final int major = _toInt(semverParts, 0);
    final int minor = _toInt(semverParts, 1);
    final int patch = _toInt(semverParts, 2);

    final int build = plusParts.length > 1
        ? int.tryParse(plusParts[1]) ?? 0
        : 0;
    return _VersionParts(
      major: major,
      minor: minor,
      patch: patch,
      build: build,
    );
  }

  static int _toInt(List<String> parts, int index) {
    if (index >= parts.length) {
      return 0;
    }
    return int.tryParse(parts[index]) ?? 0;
  }
}
