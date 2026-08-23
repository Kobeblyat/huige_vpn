import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'windows_dpapi_secret_store.dart';

/// 灰哥VPN 面板账号登录服务（Windows 桌面版）
///
/// 与手机版对齐：先从云端 config.json 获取面板 API baseURL，
/// 再通过 passport/auth/login 登录取得 token 与 auth_data，
/// 依手机版订阅体系调用 user/getSubscribe 获取订阅 token，
/// 最后拼装 sub.php 订阅地址并交由订阅服务导入。
///
/// 凭据（邮箱 / auth_data / token）使用当前用户的 DPAPI 密文持久化。
class AccountService extends ChangeNotifier {
  /// 灰哥VPN 面板配置地址（config.json）与默认 API baseURL。
  static const String configUrl = 'https://vpn.tenxun.cyou/config.json';
  static const String defaultApiBase = 'https://vpn.tenxun.cyou/api/v1/';

  /// 订阅地址前缀（sub.php 由面板解析）。
  static const String subscribeBaseUrl = 'https://vpn.tenxun.cyou/sub.php';

  static const Duration requestTimeout = Duration(seconds: 15);

  final http.Client _http;
  final WindowsDpapiSecretStore _secretStore;

  String? _email;
  String? _authData;
  bool _isLoading = false;

  AccountService(
    String dataDir, {
    http.Client? client,
    WindowsDpapiSecretStore? secretStore,
  })  : _http = client ?? http.Client(),
        _secretStore = secretStore ?? WindowsDpapiSecretStore(dataDir);

  /// 已登录账号邮箱，未登录为 null。
  String? get email => _email;

  /// 是否已登录。
  bool get isLoggedIn => _email != null && _authData != null;

  bool get isLoading => _isLoading;

  /// 从 DPAPI 读取已保存的登录态并在启动时恢复。
  Future<void> restore() async {
    try {
      final saved = await _secretStore.read();
      if (saved == null || saved.isEmpty) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map<String, dynamic>) return;
      final email = decoded['email'] as String?;
      final authData = decoded['authData'] as String?;
      if ((email?.isNotEmpty ?? false) && (authData?.isNotEmpty ?? false)) {
        _email = email;
        _authData = authData;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AccountService.restore 失败: $e');
    }
  }

  /// 使用邮箱 + 密码登录，登录成功后自动保存登录态。
  Future<AccountLoginResult> login(String user, String password) async {
    if (_isLoading) {
      return const AccountLoginResult.error('正在登录，请稍候');
    }
    _isLoading = true;
    notifyListeners();

    final email = user.trim();
    try {
      final base = await _resolveApiBaseUrl();
      final loginPayload = jsonEncode({'email': email, 'password': password});
      final loginResp = await _http
          .post(Uri.parse(_joinUrl(base, 'passport/auth/login')),
              headers: const {'Content-Type': 'application/json'},
              body: loginPayload)
          .timeout(requestTimeout);

      final loginBody = _decodeJson(loginResp);
      final loginData = loginBody?['data'];
      if (loginData == null || loginData is! Map<String, dynamic>) {
        return AccountLoginResult.error(_extractMessage(loginBody, loginResp));
      }

      final token = loginData['token'] as String? ?? '';
      final authData = loginData['auth_data'] as String? ?? '';
      if (token.isEmpty || authData.isEmpty) {
        return const AccountLoginResult.error('登录响应缺少 token 或 auth_data');
      }

      await _secretStore.write(jsonEncode({
        'email': email,
        'token': token,
        'authData': authData,
      }));

      _email = email;
      _authData = authData;
      notifyListeners();
      return AccountLoginResult.success(email);
    } catch (e) {
      return AccountLoginResult.error('登录失败：$e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 拉取用户订阅 token 并返回完整订阅地址；未登录抛错。
  ///
  /// 与手机版 MainActivity 一致：调用 user/getSubscribe，
  /// 优先用返回的 token，否则从 subscribe_url 的 query 提取。
  Future<String> fetchSubscriptionUrl() async {
    final authData = _authData;
    if (authData == null || authData.isEmpty) {
      throw StateError('未登录');
    }
    final base = await _resolveApiBaseUrl();
    final resp = await _http.get(
      Uri.parse(_joinUrl(base, 'user/getSubscribe')),
      headers: {'Authorization': authData},
    ).timeout(requestTimeout);

    if (resp.statusCode != 200) {
      throw AccountApiException(
        '获取订阅失败（HTTP ${resp.statusCode}）',
        _decodeJson(resp),
      );
    }

    final body = _decodeJson(resp);
    final data = body?['data'];
    if (data == null || data is! Map<String, dynamic>) {
      throw AccountApiException('获取订阅响应缺少 data', body);
    }

    var token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      final subscribeUrl = data['subscribe_url']?.toString() ?? '';
      final uri = Uri.tryParse(subscribeUrl);
      if (uri != null) {
        token = uri.queryParameters['token'] ?? '';
      }
    }
    if (token.isEmpty) {
      throw const AccountApiException('订阅响应未包含 token');
    }

    return '$subscribeBaseUrl?token=$token';
  }

  /// 拉取账号信息（套餐 / 到期时间）。未登录抛错。
  ///
  /// v2board/xboard 面板：GET user/info，data 中携带 plan_id、plan、
  /// expire_at（Unix 秒）。用于在导入订阅前校验是否已购买有效套餐。
  Future<AccountUserInfo> fetchUserInfo() async {
    final authData = _authData;
    if (authData == null || authData.isEmpty) {
      throw StateError('未登录');
    }
    final base = await _resolveApiBaseUrl();
    final resp = await _http.get(
      Uri.parse(_joinUrl(base, 'user/info')),
      headers: {'Authorization': authData},
    ).timeout(requestTimeout);

    if (resp.statusCode != 200) {
      throw AccountApiException(
        '获取账号信息失败（HTTP ${resp.statusCode}）',
        _decodeJson(resp),
      );
    }

    final body = _decodeJson(resp);
    final data = body?['data'];
    if (data == null || data is! Map<String, dynamic>) {
      throw AccountApiException('获取账号信息响应缺少 data', body);
    }

    final planId = _parseIntValue(data['plan_id']) ?? 0;
    final plan = data['plan'];
    final planName = plan is Map
        ? plan['name']?.toString().trim()
        : data['plan_name']?.toString().trim();
    final expireAt = _parseIntValue(data['expire_at']);
    return AccountUserInfo(
      planId: planId,
      planName: planName == null || planName.isEmpty ? null : planName,
      expireAt: expireAt == null || expireAt <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expireAt * 1000),
      rawData: data,
    );
  }

  static int? _parseIntValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// 退出登录，清除本地凭据。
  Future<void> logout() async {
    _email = null;
    _authData = null;
    try {
      await _secretStore.write('');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }

  /// 从 config.json 解析 API baseURL。
  Future<String> _resolveApiBaseUrl() async {
    try {
      final resp =
          await _http.get(Uri.parse(configUrl)).timeout(requestTimeout);
      if (resp.statusCode == 200) {
        final body = _decodeJson(resp);
        if (body is Map<String, dynamic>) {
          final base = body['baseURL']?.toString() ?? '';
          if (base.isNotEmpty) {
            return base.endsWith('/') ? base : '$base/';
          }
        }
      }
    } catch (_) {}
    return defaultApiBase;
  }

  /// 拼接 base 与 path，避免 base 结尾多余斜杠产生 `//` 造成 404。
  String _joinUrl(String base, String path) {
    var trimmedBase = base;
    while (trimmedBase.endsWith('/') && trimmedBase.length > 1) {
      trimmedBase = trimmedBase.substring(0, trimmedBase.length - 1);
    }
    var trimmedPath = path;
    while (trimmedPath.startsWith('/')) {
      trimmedPath = trimmedPath.substring(1);
    }
    return '$trimmedBase/$trimmedPath';
  }

  Map<String, dynamic>? _decodeJson(http.Response resp) {
    try {
      String text;
      try {
        text = utf8.decode(resp.bodyBytes);
      } on FormatException {
        text = resp.body;
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _extractMessage(
    Map<String, dynamic>? body,
    http.Response resp,
  ) {
    final msg = body?['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    return '登录失败（HTTP ${resp.statusCode}）';
  }
}

/// 登录结果。
class AccountLoginResult {
  const AccountLoginResult.success(String this.email) : error = null;
  const AccountLoginResult.error(String this.error) : email = null;

  final String? email;
  final String? error;

  bool get isSuccess => email != null && error == null;
}

/// v2board/xboard 账号信息（套餐 / 到期时间）。
class AccountUserInfo {
  const AccountUserInfo({
    required this.planId,
    this.planName,
    this.expireAt,
    this.rawData,
  });

  final int planId;
  final String? planName;
  final DateTime? expireAt;
  final Map<String, dynamic>? rawData;

  /// 是否持有未到期的有效套餐。
  bool get hasActivePlan {
    final expiry = expireAt;
    return planId > 0 && (expiry == null || expiry.isAfter(DateTime.now()));
  }

  /// 是否已购买但已到期。
  bool get isExpired {
    final expiry = expireAt;
    return planId > 0 && expiry != null && !expiry.isAfter(DateTime.now());
  }
}

/// 面板 API 异常。
class AccountApiException implements Exception {
  const AccountApiException(this.message, [this.body]);

  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}
