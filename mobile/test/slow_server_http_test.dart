import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowServer {
  late final Uint8List certificate;
  late final HttpServer server;
  final requests = <String>[];
  final token = base64UrlEncode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');
  Completer<void>? csrfGate;
  Completer<void>? csrfReceived;
  Completer<void>? productsGate;
  Completer<void>? productsReceived;
  Completer<void>? productsBodyGate;
  Completer<void>? productsBodyStarted;
  Completer<void>? writeGate;
  Completer<void>? writeReceived;
  int writeStatus = 201;

  Future<void> start() async {
    certificate = await File('test/fixtures/localhost-test-cert.pem')
        .readAsBytes();
    final key = await File('test/fixtures/localhost-test-key.pem')
        .readAsBytes();
    final context = SecurityContext()
      ..useCertificateChainBytes(certificate)
      ..usePrivateKeyBytes(key);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      requests.add('${request.method} $path');
      request.response.headers.contentType = ContentType.json;
      if (path == '/api/csrf') {
        final gate = csrfGate;
        if (gate != null) {
          if (!(csrfReceived?.isCompleted ?? true)) csrfReceived!.complete();
          await gate.future;
        }
        request.response.cookies.add(Cookie('JSESSIONID', 'csrf-test'));
        request.response.write(
          jsonEncode({'headerName': 'X-CSRF-TOKEN', 'token': 'csrf-token'}),
        );
      } else if (path == '/api/auth/login') {
        request.response.write(
          jsonEncode({
            'token': token,
            'expiresAt': '2026-11-15T18:00:00Z',
            'username': 'admin',
            'roles': ['ROLE_ADMIN'],
          }),
        );
      } else if (path == '/api/products' && request.method == 'GET') {
        final gate = productsGate;
        if (gate != null) {
          if (!(productsReceived?.isCompleted ?? true)) {
            productsReceived!.complete();
          }
          await gate.future;
        }
        final bodyGate = productsBodyGate;
        if (bodyGate != null) {
          request.response.bufferOutput = false;
          request.response.write('[');
          await request.response.flush();
          productsBodyStarted?.complete();
          await bodyGate.future;
          request.response.write(']');
        } else {
          request.response.write('[]');
        }
      } else if (path == '/api/products' && request.method == 'POST') {
        final gate = writeGate;
        if (gate != null) {
          if (!(writeReceived?.isCompleted ?? true)) writeReceived!.complete();
          await gate.future;
        }
        request.response.statusCode = writeStatus;
        request.response.write('{}');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    } on SocketException {
      // A timed-out client may close the connection while the server is paused.
    } on HttpException {
      // The response may no longer be writable after the client times out.
    }
  }

  String get url => 'https://127.0.0.1:${server.port}/';
  String get trustedCertificate => base64Encode(certificate);

  Future<void> close() async {
    for (final gate in [csrfGate, productsGate, productsBodyGate, writeGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await server.close(force: true);
  }
}

void main() {
  late _SlowServer server;

  setUp(() async {
    server = _SlowServer();
    await server.start();
  });

  tearDown(() => server.close());

  test('login suporta uma resposta CSRF após os antigos 15 segundos', () async {
    server.csrfGate = Completer<void>();
    server.csrfReceived = Completer<void>();
    final auth = HttpAuthService(
      server.url,
      developmentCertificate: server.trustedCertificate,
    );
    var finished = false;
    final result = auth
        .login('admin', 'senha')
        .then(
          (session) {
            finished = true;
            return session;
          },
          onError: (Object error, StackTrace stack) {
            finished = true;
            Error.throwWithStackTrace(error, stack);
          },
        );
    // Register an error handler immediately, even if the assertion fails.
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    await server.csrfReceived!.future;
    await Future<void>.delayed(const Duration(milliseconds: 15500));
    expect(finished, isFalse);
    server.csrfGate!.complete();
    expect((await result).isAdmin, isTrue);
    expect(server.requests, ['GET /api/csrf', 'POST /api/auth/login']);
  });

  test('consultas e CSRF aguardam mais do que o limite de escrita', () async {
    server.csrfGate = Completer<void>();
    server.csrfReceived = Completer<void>();
    final auth = HttpAuthService.withTimeoutsForTesting(
      server.url,
      developmentCertificate: server.trustedCertificate,
      readTimeout: const Duration(seconds: 3),
      writeTimeout: const Duration(milliseconds: 150),
    );
    final login = auth.login('admin', 'senha');
    await server.csrfReceived!.future;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    server.csrfGate!.complete();
    expect((await login).isAdmin, isTrue);

    server.productsGate = Completer<void>();
    server.productsReceived = Completer<void>();
    final products = auth.products();
    await server.productsReceived!.future;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    server.productsGate!.complete();
    expect(await products, isEmpty);
    expect(server.requests, [
      'GET /api/csrf',
      'POST /api/auth/login',
      'GET /api/products',
    ]);
  });

  test('falha na espera do CSRF não envia o pedido de escrita', () async {
    final auth = HttpAuthService.withTimeoutsForTesting(
      server.url,
      developmentCertificate: server.trustedCertificate,
      readTimeout: const Duration(milliseconds: 400),
      writeTimeout: const Duration(milliseconds: 150),
    );
    await auth.login('admin', 'senha');
    server.csrfGate = Completer<void>();
    server.csrfReceived = Completer<void>();
    final result = expectLater(
      auth.createProduct('Ovos', 'bandeja', '100'),
      throwsA(
        isA<AuthException>()
            .having((e) => e.message, 'mensagem', contains('demorou'))
            .having(
              (e) => e.definitelyRejected,
              'classificação conservadora',
              false,
            ),
      ),
    );
    await server.csrfReceived!.future;
    await result;
    expect(server.requests.where((r) => r == 'POST /api/products'), isEmpty);
    server.csrfGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.requests.where((r) => r == 'POST /api/products'), isEmpty);
  });

  test('o prazo da consulta inclui cabeçalhos e corpo da resposta', () async {
    final auth = HttpAuthService.withTimeoutsForTesting(
      server.url,
      developmentCertificate: server.trustedCertificate,
      readTimeout: const Duration(seconds: 1),
      writeTimeout: const Duration(milliseconds: 300),
    );
    await auth.login('admin', 'senha');
    server.productsGate = Completer<void>();
    server.productsReceived = Completer<void>();
    server.productsBodyGate = Completer<void>();
    server.productsBodyStarted = Completer<void>();
    final result = expectLater(
      auth.products(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'mensagem',
          contains('demorou'),
        ),
      ),
    );
    await server.productsReceived!.future;
    await Future<void>.delayed(const Duration(milliseconds: 650));
    server.productsGate!.complete();
    await server.productsBodyStarted!.future;
    // The body must not receive a fresh one-second deadline of its own.
    await result.timeout(const Duration(milliseconds: 700));
    server.productsBodyGate!.complete();
  });

  test('escrita com resposta atrasada tem resultado desconhecido e não é reenviada', () async {
    final auth = HttpAuthService.withTimeoutsForTesting(
      server.url,
      developmentCertificate: server.trustedCertificate,
      readTimeout: const Duration(seconds: 2),
      writeTimeout: const Duration(milliseconds: 250),
    );
    await auth.login('admin', 'senha');
    server.writeGate = Completer<void>();
    server.writeReceived = Completer<void>();
    final result = expectLater(
      auth.createProduct('Ovos', 'bandeja', '100'),
      throwsA(
        isA<AuthException>()
            .having((e) => e.message, 'mensagem', contains('demorou'))
            .having(
              (e) => e.definitelyRejected,
              'resultado desconhecido',
              false,
            ),
      ),
    );
    await server.writeReceived!.future;
    await result;
    expect(
      server.requests.where((r) => r == 'POST /api/products'),
      hasLength(1),
    );
    server.writeGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      server.requests.where((r) => r == 'POST /api/products'),
      hasLength(1),
    );
  });

  test(
    'erro 503 numa escrita não afirma que a operação foi rejeitada',
    () async {
      final auth = HttpAuthService(
        server.url,
        developmentCertificate: server.trustedCertificate,
      );
      await auth.login('admin', 'senha');
      server.writeStatus = 503;
      await expectLater(
        auth.createProduct('Ovos', 'bandeja', '100'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.message, 'mensagem', contains('indisponível'))
              .having(
                (e) => e.definitelyRejected,
                'resultado desconhecido',
                false,
              ),
        ),
      );
      expect(
        server.requests.where((r) => r == 'POST /api/products'),
        hasLength(1),
      );
    },
  );
}
