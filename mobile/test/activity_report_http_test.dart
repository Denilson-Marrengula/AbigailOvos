import 'dart:convert';
import 'dart:io';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_report_test.dart' show reportJson;

void main() {
  test(
    'HTTPS exige administrador e recusa período errado ou relatório incompleto',
    () async {
      final certificate = await File('test/fixtures/localhost-test-cert.pem')
          .readAsBytes();
      final key = await File('test/fixtures/localhost-test-key.pem')
          .readAsBytes();
      final context = SecurityContext()
        ..useCertificateChainBytes(certificate)
        ..usePrivateKeyBytes(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      final token = base64UrlEncode(List<int>.generate(32, (i) => i))
          .replaceAll('=', '');
      var status = 200;
      var wrongPeriod = false;
      var role = 'ROLE_ADMIN';
      var calls = 0;
      Uri? lastUri;
      String? authorization;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/api/csrf':
            request.response.write(
              jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'csrf'}),
            );
          case '/api/auth/login':
            request.response.write(
              jsonEncode({
                'token': token,
                'expiresAt': '2027-01-01T00:00:00Z',
                'username': 'teste',
                'roles': [role],
                'mustChangePassword': false,
              }),
            );
          case '/api/reports/activity':
            calls++;
            lastUri = request.uri;
            authorization = request.headers.value(
              HttpHeaders.authorizationHeader,
            );
            request.response.statusCode = status;
            if (status == 200) {
              final data = reportJson();
              if (wrongPeriod) data['periodStart'] = '2026-01-01';
              request.response.write(jsonEncode(data));
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
      await auth.login('teste', 'senha-ficticia');
      final from = DateTime.utc(2026, 2, 23), to = DateTime.utc(2026, 3, 1);
      final report = await auth.activityReport(from: from, to: to);
      expect(lastUri!.queryParameters, {
        'from': '2026-02-23',
        'to': '2026-03-01',
      });
      expect(authorization, 'Bearer $token');
      expect(report.debtCustomers.single.amount, '100.10');
      wrongPeriod = true;
      await expectLater(
        auth.activityReport(from: from, to: to),
        throwsA(isA<AuthException>()),
      );
      wrongPeriod = false;
      status = 413;
      await expectLater(
        auth.activityReport(from: from, to: to),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'mensagem',
            contains('demasiado grande'),
          ),
        ),
      );
      status = 404;
      await expectLater(
        auth.activityReport(from: from, to: to),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'mensagem',
            contains('não suporta'),
          ),
        ),
      );
      final previousCalls = calls;
      role = 'ROLE_SELLER';
      final seller = HttpAuthService(
        'https://127.0.0.1:${server.port}/',
        developmentCertificate: base64Encode(certificate),
      );
      await seller.login('teste', 'senha-ficticia');
      await expectLater(
        seller.activityReport(from: from, to: to),
        throwsA(isA<AuthException>()),
      );
      expect(calls, previousCalls);
    },
  );
}
