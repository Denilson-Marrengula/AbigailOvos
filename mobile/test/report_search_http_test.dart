import 'dart:convert';
import 'dart:io';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pesquisa mantém isolamento e relatório recusa servidor antigo que ignora período', () async {
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
    var legacy = true;
    var foreignSale = false;
    Uri? lastSearch;
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
              'username': 'ana',
              'roles': ['ROLE_SELLER'],
              'mustChangePassword': false,
            }),
          );
        case '/api/sales/capabilities':
          request.response.write(
            jsonEncode({
              'sellerSalesIsolation': true,
              'adminSaleAssistance': true,
            }),
          );
        case '/api/sales/search':
          lastSearch = request.uri;
          request.response.write(
            jsonEncode({
              'page': 0,
              'hasMore': false,
              'items': [
                {
                  'id': 'teste',
                  'customerName': 'Fictício',
                  'seller': foreignSale ? 'bia' : 'ana',
                  'deliveryStatus': 'PENDING',
                  'paymentStatus': 'PENDING',
                  'total': 1,
                  'totalText': '1.00',
                  'createdAt': '2026-01-01T00:00:00Z',
                  'items': [],
                },
              ],
            }),
          );
        case '/api/reports/sales':
          request.response.write(
            jsonEncode({
              'pendingOrders': 0,
              'deliveredSales': 0,
              'cancelledOperations': 0,
              'pendingPayments': 0,
              'markedPaid': 0,
              'deliveredAmount': '0.00',
              'markedPaidAmount': '0.00',
              'pendingPaymentAmount': '0.00',
              'sellers': [],
              if (!legacy) ...{
                'periodStart': '2026-01-01',
                'periodEnd': '2026-01-31',
                'timeZone': 'Africa/Maputo',
                'unknownDeliveredDates': 0,
                'unknownPaidDates': 0,
                'unknownCancelledDates': 0,
              },
            }),
          );
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final auth = HttpAuthService(
      'https://127.0.0.1:${server.port}/',
      developmentCertificate: base64Encode(certificate),
    );
    await auth.login('ana', 'fake-password');
    final page = await auth.searchSales(
      customer: 'Cliente & nome',
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 31),
    );
    expect(page.items.single.seller, 'ana');
    expect(lastSearch!.queryParameters['customer'], 'Cliente & nome');
    expect(lastSearch!.queryParameters['from'], '2026-01-01');
    foreignSale = true;
    await expectLater(auth.searchSales(), throwsA(isA<AuthException>()));
    await expectLater(
      auth.salesReport(from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31)),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'mensagem',
          contains('não suporta'),
        ),
      ),
    );
    legacy = false;
    final report = await auth.salesReport(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 31),
    );
    expect(report.periodStart, '2026-01-01');
    expect(report.eventDatesSupported, isTrue);
  });
}
