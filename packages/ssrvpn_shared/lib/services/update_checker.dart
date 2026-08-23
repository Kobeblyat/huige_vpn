import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    this.sha256,
    this.sourceHost,
    this.fallbackDownloadUrl,
  });

  final String version;
  final String downloadUrl;
  final String changelog;
  final String? sha256;
  final String? sourceHost;
  final String? fallbackDownloadUrl;
}

class _ReleaseAsset {
  const _ReleaseAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final String downloadUrl;
}

class UpdateChecker {
  static const int maxMetadataResponseBytes = 1024 * 1024;
  static const int _maxChecksumResponseBytes = 4096;

  static String get owner => AppConstants.githubOwner;
  static String get repo => AppConstants.githubRepo;
  static final Uri primaryManifestUrl = Uri.parse(AppConstants.panelConfigUrl);

  static Uri get githubLatestReleaseUrl => Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );

  static Future<AppUpdateInfo?> checkLatest({
    required String currentVersion,
    required String assetExtension,
    String? mirrorUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      // 1. Check if panel config has custom update parameters
      try {
        final panelInfo = await _checkPanelConfig(
          currentVersion: currentVersion,
          assetExtension: assetExtension,
          mirrorUrl: mirrorUrl,
          client: httpClient,
          timeout: timeout,
        );
        if (panelInfo != null) return panelInfo;
      } catch (_) {}

      // 2. Check GitHub latest release
      return await _checkGitHub(
        currentVersion: currentVersion,
        assetExtension: assetExtension,
        mirrorUrl: mirrorUrl,
        client: httpClient,
        timeout: timeout,
      );
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static Future<AppUpdateInfo?> _checkPanelConfig({
    required String currentVersion,
    required String assetExtension,
    required String? mirrorUrl,
    required http.Client client,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(AppConstants.panelConfigUrl);
    final response = await _boundedGet(
      uri,
      client: client,
      timeout: timeout,
      maxBytes: maxMetadataResponseBytes,
      headers: {
        'Accept': 'application/json',
        'User-Agent': AppConstants.appUserAgent,
      },
    );
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return null;

    final version = (data['latestVersion'] ?? data['version'])?.toString().trim().replaceFirst(RegExp(r'^v'), '');
    if (version == null || !_isValidVersion(version)) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;

    final rawUrl = (data['downloadURL'] ?? data['windowsDownloadURL'] ?? data['downloadUrl'])?.toString().trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;

    final downloadUrl = applyMirror(rawUrl, mirrorUrl);
    final changelog = data['changelog']?.toString() ?? '发现新版本 v$version，请及时更新。';
    final sha256 = data['sha256']?.toString().trim().toLowerCase();

    return AppUpdateInfo(
      version: version,
      downloadUrl: downloadUrl,
      fallbackDownloadUrl: rawUrl,
      changelog: changelog,
      sha256: sha256,
      sourceHost: Uri.tryParse(downloadUrl)?.host,
    );
  }

  static Future<AppUpdateInfo?> _checkGitHub({
    required String currentVersion,
    required String assetExtension,
    required String? mirrorUrl,
    required http.Client client,
    required Duration timeout,
  }) async {
    final response = await _boundedGet(
      githubLatestReleaseUrl,
      client: client,
      timeout: timeout,
      maxBytes: maxMetadataResponseBytes,
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': AppConstants.appUserAgent,
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'GitHub update metadata returned HTTP ${response.statusCode}',
        uri: githubLatestReleaseUrl,
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('GitHub update metadata is not an object');
    }

    final latestVersion = (data['tag_name']?.toString() ?? '').replaceFirst(
      RegExp(r'^v'),
      '',
    );
    if (!_isValidVersion(latestVersion)) {
      throw const FormatException('GitHub release version is invalid');
    }
    if (compareVersions(latestVersion, currentVersion) <= 0) return null;

    final releaseAssets = _releaseAssets(data['assets']);
    final selectedAsset = _assetFor(releaseAssets, assetExtension);
    if (selectedAsset == null) return null;

    final rawDownloadUrl = selectedAsset.downloadUrl;
    final downloadUrl = applyMirror(rawDownloadUrl, mirrorUrl);

    final sha256 = await _sha256ForAsset(
      releaseAssets,
      selectedAsset,
      latestVersion,
      mirrorUrl,
      client,
      timeout,
    );

    final sourceHost = Uri.parse(downloadUrl).host;

    return AppUpdateInfo(
      version: latestVersion,
      downloadUrl: downloadUrl,
      fallbackDownloadUrl: rawDownloadUrl,
      changelog: _buildChangelog(
        data['body']?.toString() ?? '',
        sourceHost: sourceHost,
        sha256: sha256,
      ),
      sha256: sha256,
      sourceHost: sourceHost,
    );
  }

  static String applyMirror(String rawUrl, String? mirror) {
    if (mirror == null || mirror.trim().isEmpty) return rawUrl;
    final prefix = mirror.trim().endsWith('/') ? mirror.trim() : '${mirror.trim()}/';
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return '$prefix$rawUrl';
    }
    return rawUrl;
  }

  static bool _isValidVersion(String version) =>
      RegExp(r'^\d+(?:\.\d+){1,3}$').hasMatch(version);

  static int compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai > bi) return 1;
      if (ai < bi) return -1;
    }
    return 0;
  }

  static List<_ReleaseAsset> _releaseAssets(Object? assets) {
    if (assets is! List) return const [];
    final result = <_ReleaseAsset>[];
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name']?.toString();
      final candidate = asset['browser_download_url']?.toString();
      if (name != null &&
          name.isNotEmpty &&
          candidate != null &&
          _isSecureDownloadUrl(candidate)) {
        result.add(_ReleaseAsset(name: name, downloadUrl: candidate));
      }
    }
    return result;
  }

  static _ReleaseAsset? _assetFor(
    List<_ReleaseAsset> assets,
    String assetExtension,
  ) {
    final wantedName = _assetNameForExtension(assetExtension);
    final ext = assetExtension.trim().toLowerCase();

    // 1. Try exact name match
    if (wantedName != null) {
      for (final asset in assets) {
        if (asset.name.toLowerCase() == wantedName.toLowerCase()) return asset;
      }
    }

    // 2. Try extension match
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (ext == '.exe') {
        if (name.endsWith('.exe') || name.endsWith('.zip')) return asset;
      } else if (name.endsWith(ext)) {
        return asset;
      }
    }
    return null;
  }

  static String? _assetNameForExtension(String assetExtension) {
    return switch (assetExtension.trim().toLowerCase()) {
      '.apk' => '灰哥VPN.apk',
      '.dmg' => '灰哥VPN.dmg',
      '.exe' => 'SSRVPN_Setup.exe',
      _ => null,
    };
  }

  static bool _isSecureDownloadUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  static Future<String?> _sha256ForAsset(
    List<_ReleaseAsset> assets,
    _ReleaseAsset asset,
    String version,
    String? mirrorUrl,
    http.Client client,
    Duration timeout,
  ) async {
    final checksumName = '${asset.name}.sha256'.toLowerCase();
    _ReleaseAsset? checksumAsset;
    for (final candidate in assets) {
      if (candidate.name.toLowerCase() == checksumName) {
        checksumAsset = candidate;
        break;
      }
    }
    if (checksumAsset == null) return null;

    final checksumUrl = applyMirror(checksumAsset.downloadUrl, mirrorUrl);

    try {
      final response = await _boundedGet(
        Uri.parse(checksumUrl),
        client: client,
        timeout: timeout,
        maxBytes: _maxChecksumResponseBytes,
      );
      if (response.statusCode != 200) return null;

      final checksumLine = RegExp(
        '^\\s*([a-fA-F0-9]{64})',
        multiLine: true,
      ).firstMatch(response.body);
      return checksumLine?.group(1)?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static Future<_BoundedTextResponse> _boundedGet(
    Uri uri, {
    required http.Client client,
    required Duration timeout,
    required int maxBytes,
    Map<String, String>? headers,
  }) async {
    final clock = Stopwatch()..start();
    final request = http.Request('GET', uri);
    if (headers != null) request.headers.addAll(headers);
    final responseFuture = client.send(request);
    late final http.StreamedResponse response;
    try {
      response = await responseFuture.timeout(_remainingTime(clock, timeout));
    } catch (_) {
      unawaited(
        responseFuture.then<void>(
          _cancelUnusedResponse,
          onError: (Object _, StackTrace __) {},
        ),
      );
      rethrow;
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      await _cancelUnusedResponse(response);
      throw StateError('update response exceeds $maxBytes bytes');
    }
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    final iterator = StreamIterator<List<int>>(response.stream);
    try {
      while (
          await iterator.moveNext().timeout(_remainingTime(clock, timeout))) {
        final chunk = iterator.current;
        received += chunk.length;
        if (received > maxBytes) {
          throw StateError('update response exceeds $maxBytes bytes');
        }
        bytes.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    return _BoundedTextResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes()),
    );
  }

  static Duration _remainingTime(Stopwatch clock, Duration timeout) {
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('update request timed out');
    }
    return remaining;
  }

  static Future<void> _cancelUnusedResponse(
    http.StreamedResponse response,
  ) async {
    try {
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
    } catch (_) {
      // Preserve the request failure that made this response obsolete.
    }
  }

  static String _buildChangelog(
    String body, {
    required String? sourceHost,
    required String? sha256,
  }) {
    final lines = <String>[];
    final trimmedBody = _normalizeReleaseNotes(body.trim());
    if (trimmedBody.isNotEmpty) lines.add(trimmedBody);
    if (sourceHost != null && sourceHost.isNotEmpty) {
      lines.add('下载来源: $sourceHost');
    }
    if (sha256 != null && sha256.isNotEmpty) {
      lines.add('SHA256: $sha256');
    }
    return lines.join('\n\n');
  }

  static String _normalizeReleaseNotes(String body) {
    if (body.isEmpty) return body;
    final replacements = <String, String>{
      '### Downloads': '### 下载',
      '### Added': '### 新增',
      '### Changed': '### 变更',
      '### Deprecated': '### 废弃',
      '### Removed': '### 移除',
      '### Fixed': '### 修复',
      '### Security': '### 安全',
      '| Platform | File | Checksum |': '| 平台 | 文件 | 校验和 |',
      'Verify checksums:': '校验 SHA256：',
    };
    var normalized = body;
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }
}

class _BoundedTextResponse {
  const _BoundedTextResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
