import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ssrvpn_windows/services/account_service.dart';
import 'package:ssrvpn_windows/services/windows_dpapi_secret_store.dart';

Future<Uint8List> _fakeCipher(Uint8List input) async => input;

Future<void> _fakeReplace(File source, File destination) async {}

Future<void> _fakeMoveExclusive(File source, File destination) async {}

http.Response _jsonResponse(Object body, int statusCode) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), statusCode);

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request
        ? request.body
        : await request.finalize().bytesToString();
    final response = await handler(
      http.Request(request.method, request.url)..bodyBytes = utf8.encode(body),
    );
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('AccountUserInfo', () {
    test('hasActivePlan requires a plan id and a future expiry', () {
      final now = DateTime.now();
      final active = AccountUserInfo(
        planId: 1,
        planName: '月付套餐',
        expireAt: now.add(const Duration(days: 30)),
      );
      expect(active.hasActivePlan, isTrue);

      final noPlan = AccountUserInfo(planId: 0, planName: null, expireAt: null);
      expect(noPlan.hasActivePlan, isFalse);

      final expired = AccountUserInfo(
        planId: 1,
        planName: '月付套餐',
        expireAt: now.subtract(const Duration(days: 1)),
      );
      expect(expired.hasActivePlan, isFalse);
      expect(expired.isExpired, isTrue);

      final perpetual = AccountUserInfo(planId: 2, expireAt: null);
      expect(perpetual.hasActivePlan, isTrue);
      expect(perpetual.isExpired, isFalse);
    });
  });

  group('AccountService plan gate', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('ssrvpn_account_test_');
    });

    tearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    AccountService createService(
      Future<http.Response> Function(http.Request) handler,
    ) {
      return AccountService(
        directory.path,
        client: _MockHttpClient(handler),
        secretStore: WindowsDpapiSecretStore(
          directory.path,
          protect: _fakeCipher,
          unprotect: _fakeCipher,
          replaceFile: _fakeReplace,
          isolateFile: _fakeMoveExclusive,
        ),
      );
    }

    Future<AccountService> loginAndGetService(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      final service = createService(handler);
      final result = await service.login('user@example.com', 'password');
      expect(result.isSuccess, isTrue);
      return service;
    }

    http.Response loginResponse() => _jsonResponse(
          {
            'data': {
              'token': 'token',
              'auth_data': 'auth-data',
            },
          },
          200,
        );

    test('login + user/info with an active plan allows import', () async {
      final service = await loginAndGetService((request) async {
        if (request.url.path.endsWith('/passport/auth/login')) {
          return loginResponse();
        }
        if (request.url.path.endsWith('/user/info')) {
          return _jsonResponse({
            'data': {
              'plan_id': 3,
              'plan': {'name': '季度套餐'},
              'expire_at': DateTime.now()
                      .add(const Duration(days: 90))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
          }, 200);
        }
        return http.Response('{}', 404);
      });

      final info = await service.fetchUserInfo();
      expect(info.planId, 3);
      expect(info.planName, '季度套餐');
      expect(info.expireAt, isNotNull);
      expect(info.hasActivePlan, isTrue);
    });

    test('planless account has no active plan', () async {
      final service = await loginAndGetService((request) async {
        if (request.url.path.endsWith('/passport/auth/login')) {
          return loginResponse();
        }
        if (request.url.path.endsWith('/user/info')) {
          return _jsonResponse({
            'data': {'plan_id': 0, 'plan': null, 'expire_at': 0},
          }, 200);
        }
        return http.Response('{}', 404);
      });

      final info = await service.fetchUserInfo();
      expect(info.planId, 0);
      expect(info.hasActivePlan, isFalse);
      expect(info.isExpired, isFalse);
    });

    test('expired plan is inactive and flagged expired', () async {
      final service = await loginAndGetService((request) async {
        if (request.url.path.endsWith('/passport/auth/login')) {
          return loginResponse();
        }
        if (request.url.path.endsWith('/user/info')) {
          return _jsonResponse({
            'data': {
              'plan_id': 2,
              'plan': {'name': '月付套餐'},
              'expire_at': DateTime.now()
                      .subtract(const Duration(days: 2))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
          }, 200);
        }
        return http.Response('{}', 404);
      });

      final info = await service.fetchUserInfo();
      expect(info.hasActivePlan, isFalse);
      expect(info.isExpired, isTrue);
    });

    test('user/info unauthorized surfaces an AccountApiException', () async {
      final service = await loginAndGetService((request) async {
        if (request.url.path.endsWith('/passport/auth/login')) {
          return loginResponse();
        }
        if (request.url.path.endsWith('/user/info')) {
          return _jsonResponse({'message': '未登录或登陆已过期'}, 403);
        }
        return http.Response('{}', 404);
      });

      expect(
        service.fetchUserInfo,
        throwsA(isA<AccountApiException>()),
      );
    });
  });
}
