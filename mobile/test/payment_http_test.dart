import 'dart:convert';
import 'dart:io';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPS verifica capacidade antes de enviar pagamentos e preserva CSRF', () async {
    // Chave e certificado públicos de teste; o servidor só escuta em loopback.
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

    var supportsPayment = false;
    var supportsIsolation = false;
    var supportsCustomerPhone = false;
    var duplicatePhone = false;
    final requests = <String>[];
    final writes = <Map<String, dynamic>>[];
    server.listen((request) async {
      final path = request.uri.path;
      requests.add('${request.method} $path');
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (path == '/api/me') {
        request.response.write(
          jsonEncode({
            'username': 'seller',
            'roles': ['ROLE_SELLER'],
          }),
        );
      } else if (path == '/api/sales/capabilities') {
        if (supportsPayment || supportsIsolation) {
          request.response.write(
            jsonEncode({
              'paymentMethods': supportsPayment,
              if (supportsIsolation) 'sellerSalesIsolation': true,
              if (supportsIsolation) 'adminSaleAssistance': true,
              if (supportsCustomerPhone) 'customerPhoneUnique': true,
            }),
          );
        } else {
          request.response.statusCode = 403; // comportamento do servidor V9
          request.response.write('{}');
        }
      } else if (path == '/api/csrf') {
        request.response.cookies.add(Cookie('JSESSIONID', 'test-session'));
        request.response.write(
          jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'test-token'}),
        );
      } else if (path == '/api/sales' && request.method == 'GET') {
        request.response.write(
          jsonEncode([
            {
              'id': 'old',
              'customerName': 'Antigo',
              'seller': 'seller',
              'deliveryStatus': 'DELIVERED',
              'paymentStatus': 'PAID',
              'total': 1,
              'items': [],
              'createdAt': '2026-11-11T12:00:00Z',
            },
            {
              'id': 'new',
              'customerName': 'Novo',
              'seller': 'seller',
              'deliveryStatus': 'DELIVERED',
              'paymentStatus': 'PAID',
              'paymentMethod': 'EMOLA',
              'total': 2,
              'items': [],
              'createdAt': '2026-11-11T12:00:00Z',
            },
          ]),
        );
      } else {
        writes.add({
          'path': path,
          'method': request.method,
          'body': jsonDecode(body),
          'csrf': request.headers.value('X-CSRF-TOKEN'),
          'cookie': request.headers.value('Cookie'),
          'auth': request.headers.value('Authorization'),
        });
        request.response.statusCode =
            duplicatePhone && path == '/api/customers/c1'
            ? 409
            : request.method == 'POST'
            ? 201
            : 200;
        request.response.write(
          duplicatePhone && path == '/api/customers/c1'
              ? jsonEncode({'code': 'CUSTOMER_PHONE_EXISTS'})
              : path == '/api/customers/c1'
              ? jsonEncode({'id': 'c1', 'name': 'Maria', 'phone': '821234567'})
              : '{}',
        );
      }
      await request.response.close();
    });

    final auth = HttpAuthService(
      'https://127.0.0.1:${server.port}/',
      developmentCertificate: base64Encode(certificate),
      sessionMode: false,
    );
    await auth.login('seller', 'test-password');
    final sale = {
      'paid': true,
      'paymentMethod': 'CASH',
      'customer': {'name': 'Novo', 'phone': '821234567'},
    };
    final rejected = isA<AuthException>().having(
      (e) => e.definitelyRejected,
      'não enviado',
      true,
    );
    await expectLater(auth.createSale(sale), throwsA(rejected));
    await expectLater(
      auth.changeSale('s1', 'pay', paymentMethod: PaymentMethod.mpesa),
      throwsA(rejected),
    );
    await expectLater(auth.changeSale('s1', 'deliver'), throwsA(rejected));
    await expectLater(auth.sales(), throwsA(rejected));
    expect(writes, isEmpty);
    expect(requests.where((r) => r == 'GET /api/csrf'), isEmpty);
    expect(requests.where((r) => r == 'GET /api/sales'), isEmpty);

    // V10 understands payment methods but does not isolate sellers.
    supportsPayment = true;
    await expectLater(auth.createSale({'paid': false}), throwsA(rejected));
    await expectLater(auth.sales(), throwsA(rejected));
    expect(writes, isEmpty);
    expect(requests.where((r) => r == 'GET /api/sales'), isEmpty);

    supportsIsolation = true;
    supportsPayment = false;
    await expectLater(auth.createSale(sale), throwsA(rejected));
    await expectLater(
      auth.changeSale('s1', 'pay', paymentMethod: PaymentMethod.mpesa),
      throwsA(rejected),
    );
    expect(writes, isEmpty);
    supportsPayment = true;
    await expectLater(auth.createSale(sale), throwsA(rejected));
    await expectLater(
      auth.updateCustomer('c1', 'Maria', '821234567'),
      throwsA(rejected),
    );
    expect(writes, isEmpty);
    supportsCustomerPhone = true;
    await auth.createSale(sale);
    await auth.changeSale('s1', 'pay', paymentMethod: PaymentMethod.mpesa);
    expect(writes, hasLength(2));
    expect(writes[0]['body'], sale);
    expect(writes[1]['body'], {'method': 'MPESA'});
    expect(writes[1]['path'], '/api/sales/s1/pay');
    for (final write in writes) {
      expect(write['csrf'], 'test-token');
      expect(write['cookie'], contains('JSESSIONID=test-session'));
      expect(write['auth'], startsWith('Basic '));
    }
    final sales = await auth.sales();
    expect(sales.first.paymentMethod, isNull);
    expect(paymentMethodLabel(sales.first.paymentMethod), 'Não informado');
    expect(sales.last.paymentMethod, 'EMOLA');
    final updated = await auth.updateCustomer('c1', 'Maria', '821234567');
    expect(updated.name, 'Maria');
    expect(updated.phone, '821234567');
    expect(writes.last['method'], 'PUT');
    expect(writes.last['body'], {'name': 'Maria', 'phone': '821234567'});
    expect(writes.last['csrf'], 'test-token');
    expect(writes.last['cookie'], contains('JSESSIONID=test-session'));
    duplicatePhone = true;
    await expectLater(
      auth.updateCustomer('c1', 'Maria', '821234567'),
      throwsA(
        isA<AuthException>()
            .having(
              (e) => e.code,
              'conflito de telefone',
              'CUSTOMER_PHONE_EXISTS',
            )
            .having((e) => e.definitelyRejected, 'não foi guardado', true),
      ),
    );
  });

  test(
    'HTTPS rejeita lista inconsistente e permite visão administrativa',
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
      var role = 'ROLE_SELLER';
      var includeOther = true;
      var partialCapabilities = false;
      final requests = <String>[];
      final writes = <Map<String, String?>>[];
      server.listen((request) async {
        final path = request.uri.path;
        requests.add('${request.method} $path');
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        if (path == '/api/me') {
          request.response.write(
            jsonEncode({
              'username': role == 'ROLE_ADMIN' ? 'admin' : 'ana',
              'roles': [role],
            }),
          );
        } else if (path == '/api/sales/capabilities') {
          request.response.write(
            jsonEncode({
              'paymentMethods': true,
              'sellerSalesIsolation': true,
              'adminSaleAssistance': !partialCapabilities,
            }),
          );
        } else if (path == '/api/csrf') {
          request.response.cookies.add(Cookie('JSESSIONID', 'test-session'));
          request.response.write(
            jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'test-token'}),
          );
        } else if (path == '/api/sales' && request.method == 'GET') {
          Map<String, Object> row(String seller) => {
            'id': seller,
            'customerName': 'Cliente $seller',
            'seller': seller,
            'deliveryStatus': 'PENDING',
            'paymentStatus': 'PENDING',
            'total': 1,
            'items': <Object>[],
            'createdAt': '2026-11-11T12:00:00Z',
          };
          request.response.write(
            jsonEncode([
              row('ana'),
              if (includeOther) row('Ana'),
              if (includeOther) row('bia'),
            ]),
          );
        } else {
          writes.add({
            'path': path,
            'csrf': request.headers.value('X-CSRF-TOKEN'),
            'cookie': request.headers.value('Cookie'),
          });
          request.response.write('{}');
        }
        await request.response.close();
      });
      final auth = HttpAuthService(
        'https://127.0.0.1:${server.port}/',
        developmentCertificate: base64Encode(certificate),
        sessionMode: false,
      );
      await auth.login('ana', 'test-password');
      await expectLater(auth.sales(), throwsA(isA<AuthException>()));
      includeOther = false;
      expect((await auth.sales()).map((sale) => sale.seller), ['ana']);
      partialCapabilities = true;
      final listCalls = requests.where((r) => r == 'GET /api/sales').length;
      await expectLater(auth.sales(), throwsA(isA<AuthException>()));
      await expectLater(
        auth.changeSale('ana', 'deliver'),
        throwsA(isA<AuthException>()),
      );
      expect(requests.where((r) => r == 'GET /api/sales').length, listCalls);
      expect(writes, isEmpty);
      partialCapabilities = false;
      includeOther = true;
      await auth.logout();
      role = 'ROLE_ADMIN';
      await auth.login('admin', 'test-password');
      expect((await auth.sales()).map((sale) => sale.seller), [
        'ana',
        'Ana',
        'bia',
      ]);
      await auth.changeSale('ana', 'deliver');
      await auth.changeSale('ana', 'pay', paymentMethod: PaymentMethod.cash);
      expect(writes.map((write) => write['path']), [
        '/api/sales/ana/deliver',
        '/api/sales/ana/pay',
      ]);
      for (final write in writes) {
        expect(write['csrf'], 'test-token');
        expect(write['cookie'], contains('JSESSIONID=test-session'));
      }
    },
  );

  test('HTTPS transporta redefinição e troca obrigatória com CSRF', () async {
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
    const temporary = '0123456789abcdefghijklmnopqrstuv';
    var admin = true;
    final writes = <Map<String, dynamic>>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/me':
          request.response.write(
            jsonEncode({
              'username': admin ? 'admin' : 'ana',
              'roles': [admin ? 'ROLE_ADMIN' : 'ROLE_SELLER'],
              'mustChangePassword': !admin,
            }),
          );
        case '/api/csrf':
          request.response.cookies.add(Cookie('JSESSIONID', 'test-session'));
          request.response.write(
            jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'test-token'}),
          );
        default:
          writes.add({
            'path': request.uri.path,
            'method': request.method,
            'body': body.isEmpty ? null : jsonDecode(body),
            'csrf': request.headers.value('X-CSRF-TOKEN'),
            'cookie': request.headers.value('Cookie'),
          });
          request.response.write(
            request.uri.path.endsWith('/password-reset')
                ? jsonEncode({
                    'temporaryPassword': temporary,
                    'expiresAt': '2026-11-15T12:00:00Z',
                  })
                : jsonEncode({'changed': true}),
          );
      }
      await request.response.close();
    });
    final auth = HttpAuthService(
      'https://127.0.0.1:${server.port}/',
      developmentCertificate: base64Encode(certificate),
      sessionMode: false,
    );
    await auth.login('admin', 'test-password');
    final reset = await auth.resetSellerPassword('seller1');
    expect(reset.value, temporary);
    expect(reset.expiresAt.isUtc, isTrue);
    expect(writes.single['path'], '/api/users/seller1/password-reset');
    expect(writes.single['method'], 'PATCH');
    expect(writes.single['body'], isNull);
    admin = false;
    final session = await auth.login('ana', temporary);
    expect(session.mustChangePassword, isTrue);
    await auth.changePassword(temporary, 'nova-senha-forte');
    expect(writes.last['path'], '/api/account/password');
    expect(writes.last['method'], 'PUT');
    expect(writes.last['body'], {
      'currentPassword': temporary,
      'newPassword': 'nova-senha-forte',
    });
    for (final write in writes) {
      expect(write['csrf'], 'test-token');
      expect(write['cookie'], contains('JSESSIONID=test-session'));
    }
    await expectLater(
      auth.products(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.sessionExpired,
          'sessão terminada',
          true,
        ),
      ),
    );
  });
}
