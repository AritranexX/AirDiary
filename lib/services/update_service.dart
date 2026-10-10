import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Representation of an in-app GitHub Release update payload
class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String? downloadUrl;
  final String releaseUrl;
  final DateTime? publishedAt;
  final bool isChecking;
  final String? errorMessage;

  const UpdateInfo({
    this.hasUpdate = false,
    this.currentVersion = '1.2.0+3',
    this.latestVersion = '',
    this.releaseTitle = '',
    this.releaseNotes = '',
    this.downloadUrl,
    this.releaseUrl = '',
    this.publishedAt,
    this.isChecking = false,
    this.errorMessage,
  });

  UpdateInfo copyWith({
    bool? hasUpdate,
    String? currentVersion,
    String? latestVersion,
    String? releaseTitle,
    String? releaseNotes,
    String? downloadUrl,
    String? releaseUrl,
    DateTime? publishedAt,
    bool? isChecking,
    String? errorMessage,
  }) {
    return UpdateInfo(
      hasUpdate: hasUpdate ?? this.hasUpdate,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      releaseTitle: releaseTitle ?? this.releaseTitle,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      publishedAt: publishedAt ?? this.publishedAt,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// In-App GitHub Release Update Engine.
/// Silently checks `https://api.github.com/repos/AritranexX/AirDiary/releases/latest`
/// using standard native HTTP sockets with zero third-party telemetry, matches platform
/// binary distribution assets (APK, DMG, ZIP, IPA), and provides seamless in-app upgrade flows.
class UpdateService extends ChangeNotifier {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String currentAppVersion = '1.2.0+3';
  static const String githubRepoOwner = 'AritranexX';
  static const String githubRepoName = 'AirDiary';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$githubRepoOwner/$githubRepoName/releases/latest';
  static const String fallbackReleasesWebUrl =
      'https://github.com/$githubRepoOwner/$githubRepoName/releases';

  UpdateInfo _updateInfo = const UpdateInfo(currentVersion: currentAppVersion);
  UpdateInfo get updateInfo => _updateInfo;

  Timer? _periodicCheckTimer;
  bool _isDismissedForSession = false;
  bool get isDismissedForSession => _isDismissedForSession;

  /// Initialize the update checker service and schedule non-intrusive background checks
  void init() {
    // Initial silent check with delayed startup so it doesn't block app launch
    Future.delayed(const Duration(seconds: 4), () {
      checkForUpdate(silent: true);
    });

    // Periodic silent check every 4 hours
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(hours: 4), (_) {
      checkForUpdate(silent: true);
    });
  }

  /// Dismiss the in-app banner for this session
  void dismissBanner() {
    _isDismissedForSession = true;
    notifyListeners();
  }

  /// Check GitHub releases API for new release versions
  Future<UpdateInfo> checkForUpdate({bool silent = false}) async {
    _updateInfo = _updateInfo.copyWith(isChecking: true, errorMessage: null);
    notifyListeners();

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse(releasesApiUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'AirDiary-App-v$currentAppVersion');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        client.close();

        final Map<String, dynamic> data = jsonDecode(responseBody) as Map<String, dynamic>;
        final String tagName = (data['tag_name'] as String? ?? '').trim();
        final String name = (data['name'] as String? ?? tagName).trim();
        final String body = (data['body'] as String? ?? '').trim();
        final String htmlUrl = (data['html_url'] as String? ?? fallbackReleasesWebUrl).trim();
        final String? publishedAtStr = data['published_at'] as String?;
        final DateTime? publishedAt =
            publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

        final rawAssets = data['assets'] as List<dynamic>? ?? [];
        final String? platformDownloadUrl = _resolvePlatformAssetUrl(rawAssets, htmlUrl);

        final bool hasNewerVersion = _isRemoteVersionNewer(tagName, currentAppVersion);

        _updateInfo = UpdateInfo(
          hasUpdate: hasNewerVersion,
          currentVersion: currentAppVersion,
          latestVersion: tagName.isNotEmpty ? tagName : currentAppVersion,
          releaseTitle: name,
          releaseNotes: body,
          downloadUrl: platformDownloadUrl,
          releaseUrl: htmlUrl,
          publishedAt: publishedAt,
          isChecking: false,
          errorMessage: null,
        );

        if (hasNewerVersion) {
          debugPrint('[UpdateService] Update available: $tagName (Current: $currentAppVersion)');
        }
      } else if (response.statusCode == 404 || response.statusCode == 403) {
        // Rate limited or no releases published yet
        client.close();
        _updateInfo = _updateInfo.copyWith(
          isChecking: false,
          hasUpdate: false,
          errorMessage: response.statusCode == 403 ? 'GitHub API rate limit reached' : null,
        );
      } else {
        client.close();
        _updateInfo = _updateInfo.copyWith(
          isChecking: false,
          errorMessage: 'Server responded with status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] Check update error (safely handled): $e');
      _updateInfo = _updateInfo.copyWith(
        isChecking: false,
        errorMessage: silent ? null : 'Could not check for updates: $e',
      );
    }

    notifyListeners();
    return _updateInfo;
  }

  /// Match platform-specific distribution asset
  String? _resolvePlatformAssetUrl(List<dynamic> assets, String releaseHtmlUrl) {
    if (assets.isEmpty) return releaseHtmlUrl;

    String? matchedUrl;

    if (Platform.isAndroid) {
      // Find .apk asset
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') || name.contains('android')) {
          matchedUrl = asset['browser_download_url'] as String?;
          if (matchedUrl != null) return matchedUrl;
        }
      }
    } else if (Platform.isMacOS) {
      // Find .dmg or .pkg asset
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.dmg') || name.endsWith('.pkg') || name.contains('macos') || name.contains('mac')) {
          matchedUrl = asset['browser_download_url'] as String?;
          if (matchedUrl != null) return matchedUrl;
        }
      }
    } else if (Platform.isWindows) {
      // Find .zip or .exe asset
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.zip') || name.endsWith('.exe') || name.contains('windows') || name.contains('win')) {
          matchedUrl = asset['browser_download_url'] as String?;
          if (matchedUrl != null) return matchedUrl;
        }
      }
    } else if (Platform.isIOS) {
      // Find .ipa asset
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.ipa') || name.contains('ios')) {
          matchedUrl = asset['browser_download_url'] as String?;
          if (matchedUrl != null) return matchedUrl;
        }
      }
    }

    // Default to first asset or release HTML URL
    if (assets.isNotEmpty && assets.first['browser_download_url'] != null) {
      return assets.first['browser_download_url'] as String?;
    }

    return releaseHtmlUrl;
  }

  /// Semantic version comparison: returns true if remoteVersion > localVersion
  bool _isRemoteVersionNewer(String remote, String local) {
    if (remote.isEmpty) return false;

    // Clean leading 'v' or 'V'
    final cleanRemote = remote.startsWith('v') || remote.startsWith('V')
        ? remote.substring(1).trim()
        : remote.trim();
    final cleanLocal = local.startsWith('v') || local.startsWith('V')
        ? local.substring(1).trim()
        : local.trim();

    if (cleanRemote == cleanLocal) return false;

    try {
      // Split version and build number: e.g. 1.1.0+2
      final remoteParts = cleanRemote.split('+');
      final localParts = cleanLocal.split('+');

      final remoteSemver = remoteParts[0].split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final localSemver = localParts[0].split('.').map((p) => int.tryParse(p) ?? 0).toList();

      while (remoteSemver.length < 3) {
        remoteSemver.add(0);
      }
      while (localSemver.length < 3) {
        localSemver.add(0);
      }

      // Compare major, minor, patch
      for (int i = 0; i < 3; i++) {
        if (remoteSemver[i] > localSemver[i]) return true;
        if (remoteSemver[i] < localSemver[i]) return false;
      }

      // If semver is identical, compare build number if available
      final remoteBuild = remoteParts.length > 1 ? (int.tryParse(remoteParts[1]) ?? 0) : 0;
      final localBuild = localParts.length > 1 ? (int.tryParse(localParts[1]) ?? 0) : 0;

      return remoteBuild > localBuild;
    } catch (_) {
      return false;
    }
  }

  /// Launch the download URL in the external browser/system package manager
  Future<bool> launchUpdateDownload() async {
    final targetUrl = _updateInfo.downloadUrl ?? _updateInfo.releaseUrl;
    if (targetUrl.isEmpty) return false;

    final uri = Uri.parse(targetUrl);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[UpdateService] Failed to launch update URL: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    super.dispose();
  }
}
