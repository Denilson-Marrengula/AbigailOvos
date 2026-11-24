import 'dart:convert';
import 'dart:io';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sessão HTTPS usa CSRF e Bearer, sem fallback Basic', () async {
    final certificate = await File('test/fixtures/localhost-test-cert.pem')
        .readAsBytes();
    final privateKey = await File('test/fixtures/localhost-test-key.pem')
        .readAsBytes();
    final context = SecurityContext()
      ..useCertificateChainBytes(certificate)
      ..usePrivateKeyBytes(privateKey);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => server.close(force: true));

    final token = base64UrlEncode(List<int>.generate(32, (i) => i))
        .replaceAll('=', '');
    final requests = <Map<String, Object?>>[];
    var revoked = false;
    var badToken = false;
    var failLogout = false;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      final csrf = request.headers.value('X-CSRF-TOKEN');
      final cookie = request.headers.value(HttpHeaders.cookieHeader);
      requests.add({
        'path': request.uri.path,
        'method': request.method,
        'auth': auth,
        'csrf': csrf,
        'cookie': cookie,
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/csrf':
          if (auth != null && (auth != 'Bearer $token' || revoked)) {
            request.response.statusCode = 401;
          } else {
            request.response.cookies.add(Cookie('JSESSIONID', 'csrf-test'));
            request.response.write(
              jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'csrf-token'}),
            );
          }
        case '/api/auth/login':
          final data = jsonDecode(body) as Map<String, dynamic>;
          if (auth != null ||
              csrf != 'csrf-token' ||
              !(cookie?.contains('JSESSIONID=csrf-test') ?? false) ||
              data['username'] != 'admin' ||
              data['password'] != 'test-password' ||
              data.containsKey('code')) {
            request.response.statusCode = 401;
          } else {
            revoked = false;
            request.response.write(
              jsonEncode({
                'token': badToken ? 'invalid' : token,
                'expiresAt': '2026-11-15T18:00:00Z',
                'username': 'admin',
                'roles': ['ROLE_ADMIN'],
                'mustChangePassword': false,
              }),
            );
          }
        case '/api/products':
          if (auth != 'Bearer $token' || revoked) {
            request.response.statusCode = 401;
          } else {
            request.response.write('[]');
          }
        case '/api/auth/logout':
          if (failLogout) {
            request.response.statusCode = 503;
          } else if (auth != 'Bearer $token' ||
              csrf != 'csrf-token' ||
              !(cookie?.contains('JSESSIONID=csrf-test') ?? false)) {
            request.response.statusCode = 403;
          } else {
            revoked = true;
            request.response.statusCode = 204;
          }
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final auth = HttpAuthService(
      'https://127.0.0.1:${server.port}/',
      developmentCertificate: base64Encode(certificate),
    );
    await expectLater(
      auth.login('admin', 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
    final session = await auth.login('admin', 'test-password');
    expect(session.isAdmin, isTrue);
    expect(await auth.products(), isEmpty);
    await auth.logout();
    expect(revoked, isTrue);
    await expectLater(
      auth.products(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.sessionExpired,
          'sessão local',
          true,
        ),
      ),
    );
    expect(requests.where((r) => r['path'] == '/api/me'), isEmpty);
    expect(
      requests.every((r) => !(r['auth'] as String? ?? '').startsWith('Basic ')),
      isTrue,
    );
    final logins = requests
        .where((r) => r['path'] == '/api/auth/login')
        .toList();
    expect(logins.last['csrf'], 'csrf-token');
    expect(logins.last['cookie'], contains('JSESSIONID=csrf-test'));
    expect((logins.last['body'] as Map).containsKey('code'), isFalse);

    badToken = true;
    await expectLater(
      auth.login('admin', 'test-password'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(auth.products(), throwsA(isA<AuthException>()));
    badToken = false;
    await auth.login('admin', 'test-password');
    failLogout = true;
    await expectLater(auth.logout(), throwsA(isA<AuthException>()));
    await expectLater(
      auth.products(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.sessionExpired,
          'sessão local',
          true,
        ),
      ),
    );
  });
}
