import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.version,
    required this.releaseUri,
  });

  final String version;
  final Uri releaseUri;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.latestRelease,
    required this.hasUpdate,
  });

  final String currentVersion;
  final GithubReleaseInfo latestRelease;
  final bool hasUpdate;
}

typedef GithubReleaseResolver = Future<GithubReleaseInfo> Function();

class GithubAppUpdateService {
  GithubAppUpdateService({
    this.releaseResolver,
    Uri? repoHomepageUri,
    Uri? latestReleaseLookupUri,
    this.clientFactory = _defaultHttpClientFactory,
  })  : repoHomepageUri = repoHomepageUri ?? repoHomepageUriDefault,
        latestReleaseLookupUri =
            latestReleaseLookupUri ?? latestReleaseLookupUriDefault;

  static final Uri repoHomepageUriDefault =
      Uri(scheme: 'https', host: 'github.com', path: '/leonardkorir/Nolive');
  static final Uri latestReleaseLookupUriDefault = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/leonardkorir/Nolive/releases/latest',
  );

  final GithubReleaseResolver? releaseResolver;
  final Uri repoHomepageUri;
  final Uri latestReleaseLookupUri;
  final HttpClient Function() clientFactory;

  static HttpClient _defaultHttpClientFactory() => HttpClient();

  static Future<String> loadInstalledVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  Future<AppUpdateCheckResult> checkForUpdate({String? currentVersion}) async {
    final installedVersion = currentVersion ?? await loadInstalledVersion();
    final latestRelease = await fetchLatestRelease();
    return AppUpdateCheckResult(
      currentVersion: installedVersion,
      latestRelease: latestRelease,
      hasUpdate: compareVersions(latestRelease.version, installedVersion) > 0,
    );
  }

  Future<GithubReleaseInfo> fetchLatestRelease() async {
    final override = releaseResolver;
    if (override != null) {
      return override();
    }

    final client = clientFactory();
    try {
      final request = await client.getUrl(latestReleaseLookupUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Nolive-App');
      final response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();

      if (location == null || location.isEmpty) {
        throw const FormatException('GitHub release redirect missing.');
      }

      final releaseUri = latestReleaseLookupUri.resolve(location);
      final version = _versionFromReleaseUri(releaseUri);
      return GithubReleaseInfo(version: version, releaseUri: releaseUri);
    } finally {
      client.close(force: true);
    }
  }

  static int compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < maxLength; index += 1) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) {
        return leftPart.compareTo(rightPart);
      }
    }
    return 0;
  }

  static String _versionFromReleaseUri(Uri releaseUri) {
    final tag =
        releaseUri.pathSegments.isEmpty ? '' : releaseUri.pathSegments.last;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (version.isEmpty) {
      throw const FormatException('Invalid GitHub release tag.');
    }
    return version;
  }

  static List<int> _parseVersion(String version) {
    final normalized = version.trim().replaceFirst(RegExp(r'^[^0-9]+'), '');
    final core = normalized.split(RegExp(r'[-+]')).first;
    if (core.isEmpty) {
      return const [0];
    }
    return core
        .split('.')
        .map(
            (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList(growable: false);
  }
}
