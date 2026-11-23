import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AuthSession {
  const AuthSession({required this.username, required this.roles});
  final String username;
  final List<String> roles;
  bool get isAdmin => roles.contains('ROLE_ADMIN');
}

abstract interface class AuthService {
  Future<AuthSession> login(String username, String password);
  Future<List<Product>> products();
  Future<List<Customer>> customers();
  Future<Customer> createCustomer(String name, String? phone);
  Future<StockBalance> stockBalance(String productId);
  Future<void> createStockMovement(Map<String, dynamic> request);
  Future<List<SaleRecord>> sales();
  Future<SalesReport> salesReport();
  Future<void> createSale(Map<String, dynamic> request);
  Future<void> changeSale(String id, String action);
  Future<List<SellerAccount>> sellers();
  Future<void> createSeller(
    String username,
    String password,
    String name,
    String? phone,
  );
  Future<void> updateSeller(String id, String name, String? phone);
  Future<void> setSellerEnabled(String id, bool enabled);
  void logout();
}

class SellerPerformance {
  const SellerPerformance({
    required this.seller,
    required this.deliveredCount,
    required this.deliveredAmount,
  });
  final String seller;
  final int deliveredCount;
  final String deliveredAmount;
}

class SalesReport {
  const SalesReport({
    required this.pendingOrders,
    required this.deliveredSales,
    required this.cancelledOperations,
    required this.pendingPayments,
    required this.markedPaid,
    required this.deliveredAmount,
    required this.markedPaidAmount,
    required this.pendingPaymentAmount,
    required this.sellers,
  });
  final int pendingOrders;
  final int deliveredSales;
  final int cancelledOperations;
  final int pendingPayments;
  final int markedPaid;
  final String deliveredAmount;
  final String markedPaidAmount;
  final String pendingPaymentAmount;
  final List<SellerPerformance> sellers;
}

class SellerAccount {
  const SellerAccount({
    required this.id,
    required this.username,
    required this.enabled,
    this.displayName,
    this.phone,
  });
  final String id;
  final String username;
  final bool enabled;
  final String? displayName;
  final String? phone;
}

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.customerName,
    required this.seller,
    required this.delivery,
    required this.payment,
    required this.total,
    required this.items,
    this.totalText,
    this.createdAt,
  });
  final String id;
  final String customerName;
  final String seller;
  final String delivery;
  final String payment;
  final num total;
  final String? totalText;
  final List<String> items;
  final DateTime? createdAt;
}

class StockBalance {
  const StockBalance({
    required this.physical,
    required this.reserved,
    required this.available,
  });
  final num physical;
  final num reserved;
  final num available;
}

class Product {
  const Product({
    this.id = '',
    required this.name,
    required this.unit,
    required this.price,
    this.active = true,
  });
  final String id;
  final String name;
  final String unit;
  final String price;
  final bool active;
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.createdAt,
  });
  final String id;
  final String name;
  final String? phone;
  final DateTime? createdAt;
}

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.sessionExpired = false,
    this.definitelyRejected = false,
  });
  final String message;

  final bool sessionExpired;
  final bool definitelyRejected;
}

class _RawResponse {
  const _RawResponse(this.status, this.text, this.cookies);
  final int status;
  final String text;
  final List<Cookie> cookies;
}

class HttpAuthService implements AuthService {
  HttpAuthService(this.baseUrl, {this.developmentCertificate = ''});
  final String baseUrl;
  final String developmentCertificate;
  String? _authorization;
  static const _timeout = Duration(seconds: 15);
  static const _invalidResponse = AuthException(
    'Resposta inválida do servidor.',
  );

  @override
  Future<AuthSession> login(String username, String password) async {
    _authorization = null;
    final authorization =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    final data = await _send('GET', 'api/me', authorization, login: true);
    if (data is! Map<String, dynamic> ||
        data['username'] is! String ||
        data['roles'] is! List) {
      throw _invalidResponse;
    }
    final roles = (data['roles'] as List).whereType<String>().toList();
    if (!roles.contains('ROLE_ADMIN') && !roles.contains('ROLE_SELLER')) {
      throw const AuthException('Esta conta não tem um perfil autorizado.');
    }
    _authorization = authorization;
    return AuthSession(username: data['username'] as String, roles: roles);
  }

  @override
  void logout() {
    _authorization = null;
  }

  @override
  Future<List<Product>> products() async {
    final data = await _send('GET', 'api/products', _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    return data.map((item) {
      if (item is! Map ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['unit'] is! String ||
          item['price'] is! num) {
        throw _invalidResponse;
      }
      return Product(
        id: item['id'] as String,
        name: item['name'] as String,
        unit: item['unit'] as String,
        price: item['priceText'] is String
            ? item['priceText'] as String
            : item['price'].toString(),
        active: item['active'] is bool ? item['active'] as bool : true,
      );
    }).toList();
  }

  @override
  Future<List<Customer>> customers() async {
    final data = await _send('GET', 'api/customers', _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    return data.map(_customerFrom).toList();
  }

  @override
  Future<Customer> createCustomer(String name, String? phone) async {
    final data = await _send(
      'POST',
      'api/customers',
      _requireAuthorization(),
      body: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
    return _customerFrom(data);
  }

  @override
  Future<StockBalance> stockBalance(String productId) async {
    final data = await _send(
      'GET',
      'api/stock/${Uri.encodeComponent(productId)}',
      _requireAuthorization(),
    );
    if (data is! Map ||
        data['quantity'] is! num ||
        data['reserved'] is! num ||
        data['available'] is! num) {
      throw _invalidResponse;
    }
    return StockBalance(
      physical: data['quantity'] as num,
      reserved: data['reserved'] as num,
      available: data['available'] as num,
    );
  }

  @override
  Future<void> createStockMovement(Map<String, dynamic> request) async {
    await _send(
      'POST',
      'api/stock/movements',
      _requireAuthorization(),
      body: request,
    );
  }

  @override
  Future<List<SaleRecord>> sales() async {
    final data = await _send('GET', 'api/sales', _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    return data.map((item) {
      if (item is! Map ||
          item['id'] is! String ||
          item['customerName'] is! String ||
          item['seller'] is! String ||
          item['deliveryStatus'] is! String ||
          item['paymentStatus'] is! String ||
          item['total'] is! num ||
          (item['totalText'] != null && item['totalText'] is! String) ||
          item['items'] is! List ||
          item['createdAt'] is! String ||
          DateTime.tryParse(item['createdAt'] as String) == null) {
        throw _invalidResponse;
      }
      final lines = (item['items'] as List).map((line) {
        if (line is! Map ||
            line['productName'] is! String ||
            line['quantity'] is! num ||
            line['unit'] is! String) {
          throw _invalidResponse;
        }
        return '${line['quantity']} ${line['unit']} · ${line['productName']}';
      }).toList();
      return SaleRecord(
        id: item['id'],
        customerName: item['customerName'],
        seller: item['seller'],
        delivery: item['deliveryStatus'],
        payment: item['paymentStatus'],
        total: item['total'],
        totalText: item['totalText'] as String?,
        items: lines,
        createdAt: DateTime.parse(item['createdAt'] as String),
      );
    }).toList();
  }

  @override
  Future<SalesReport> salesReport() async {
    final data = await _send(
      'GET',
      'api/reports/sales',
      _requireAuthorization(),
    );
    bool money(dynamic value) =>
        value is String && RegExp(r'^\d+\.\d{2}$').hasMatch(value);
    if (data is! Map ||
        data['pendingOrders'] is! int ||
        data['deliveredSales'] is! int ||
        data['cancelledOperations'] is! int ||
        data['pendingPayments'] is! int ||
        data['markedPaid'] is! int ||
        !money(data['deliveredAmount']) ||
        !money(data['markedPaidAmount']) ||
        !money(data['pendingPaymentAmount']) ||
        data['sellers'] is! List) {
      throw _invalidResponse;
    }
    final sellers = (data['sellers'] as List).map((item) {
      if (item is! Map ||
          item['seller'] is! String ||
          item['deliveredCount'] is! int ||
          !money(item['deliveredAmount'])) {
        throw _invalidResponse;
      }
      return SellerPerformance(
        seller: item['seller'],
        deliveredCount: item['deliveredCount'],
        deliveredAmount: item['deliveredAmount'],
      );
    }).toList();
    return SalesReport(
      pendingOrders: data['pendingOrders'],
      deliveredSales: data['deliveredSales'],
      cancelledOperations: data['cancelledOperations'],
      pendingPayments: data['pendingPayments'],
      markedPaid: data['markedPaid'],
      deliveredAmount: data['deliveredAmount'],
      markedPaidAmount: data['markedPaidAmount'],
      pendingPaymentAmount: data['pendingPaymentAmount'],
      sellers: sellers,
    );
  }

  @override
  Future<void> createSale(Map<String, dynamic> request) async {
    await _send('POST', 'api/sales', _requireAuthorization(), body: request);
  }

  @override
  Future<void> changeSale(String id, String action) async {
    if (!const {'deliver', 'cancel', 'pay'}.contains(action)) {
      throw _invalidResponse;
    }
    await _send(
      'PATCH',
      'api/sales/${Uri.encodeComponent(id)}/$action',
      _requireAuthorization(),
    );
  }

  @override
  Future<List<SellerAccount>> sellers() async {
    final data = await _send('GET', 'api/users', _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    final result = <SellerAccount>[];
    for (final item in data) {
      if (item is! Map || item['role'] is! String) throw _invalidResponse;
      if (item['role'] != 'SELLER') continue;
      if (item['id'] is! String ||
          item['username'] is! String ||
          item['enabled'] is! bool ||
          (item['displayName'] != null && item['displayName'] is! String) ||
          (item['phone'] != null && item['phone'] is! String)) {
        throw _invalidResponse;
      }
      result.add(
        SellerAccount(
          id: item['id'],
          username: item['username'],
          enabled: item['enabled'],
          displayName: item['displayName'],
          phone: item['phone'],
        ),
      );
    }
    return result;
  }

  @override
  Future<void> createSeller(
    String username,
    String password,
    String name,
    String? phone,
  ) async {
    await _send(
      'POST',
      'api/users',
      _requireAuthorization(),
      body: {
        'username': username,
        'password': password,
        'displayName': name,
        'phone': phone,
      },
    );
  }

  @override
  Future<void> updateSeller(String id, String name, String? phone) async {
    await _send(
      'PUT',
      'api/users/${Uri.encodeComponent(id)}/profile',
      _requireAuthorization(),
      body: {'displayName': name, 'phone': phone},
    );
  }

  @override
  Future<void> setSellerEnabled(String id, bool enabled) async {
    await _send(
      'PATCH',
      'api/users/${Uri.encodeComponent(id)}/status',
      _requireAuthorization(),
      body: {'enabled': enabled},
    );
  }

  Customer _customerFrom(dynamic item) {
    if (item is! Map || item['id'] is! String || item['name'] is! String) {
      throw _invalidResponse;
    }
    final phone = item['phone'];
    final created = item['createdAt'];
    return Customer(
      id: item['id'] as String,
      name: item['name'] as String,
      phone: phone is String && phone.trim().isNotEmpty ? phone : null,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  String _requireAuthorization() {
    final authorization = _authorization;
    if (authorization == null) {
      throw const AuthException(
        'Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    return authorization;
  }

  Uri _baseUri() {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AuthException(
        'Configure um endereço HTTPS válido para o servidor.',
      );
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  HttpClient _newClient(Uri uri) {
    SecurityContext? securityContext;
    if (developmentCertificate.isNotEmpty) {
      if (!kDebugMode || (uri.host != '10.0.2.2' && uri.host != '127.0.0.1')) {
        throw const AuthException(
          'Certificado de desenvolvimento não permitido.',
        );
      }
      try {
        // Isolate the local test trust anchor; never replace platform roots globally.
        securityContext = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificatesBytes(base64Decode(developmentCertificate));
      } catch (_) {
        throw const AuthException('Certificado de desenvolvimento inválido.');
      }
    }
    return HttpClient(context: securityContext)..connectionTimeout = _timeout;
  }

  Future<_RawResponse> _call(
    HttpClient client,
    Uri base,
    String method,
    String path,
    String authorization,
    Map<String, String> headers,
    Object? body,
  ) async {
    final request = await client
        .openUrl(method, base.resolve(path))
        .timeout(_timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(_timeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
    return _RawResponse(response.statusCode, text, response.cookies);
  }

  void _check(_RawResponse response, {required bool login, required int ok}) {
    if (response.status == ok) return;
    const loginFailed =
        'Não foi possível iniciar sessão. Verifique os dados de acesso.';
    switch (response.status) {
      case 401:
        throw AuthException(
          login ? loginFailed : 'A sessão terminou. Inicie sessão novamente.',
          sessionExpired: !login,
        );
      case 403:
        throw AuthException(
          login ? loginFailed : 'Não tem permissão para esta operação.',
          definitelyRejected: true,
        );
      case 400:
        throw const AuthException(
          'Dados inválidos. Verifique os campos e tente novamente.',
          definitelyRejected: true,
        );
      case 409:
        throw const AuthException(
          'Operação não permitida, preço alterado ou stock disponível insuficiente. Atualize os dados.',
          definitelyRejected: true,
        );
      default:
        throw const AuthException(
          'O servidor não conseguiu processar o pedido.',
        );
    }
  }

  dynamic _decode(_RawResponse response) =>
      response.text.isEmpty ? null : jsonDecode(response.text);

  /// Envia o pedido. Operações que alteram dados obtêm antes o token CSRF
  /// (e o cookie de sessão que o acompanha), como exige o backend.
  Future<dynamic> _send(
    String method,
    String path,
    String authorization, {
    Object? body,
    bool login = false,
  }) async {
    final base = _baseUri();
    final client = _newClient(base);
    try {
      final headers = <String, String>{};
      if (method != 'GET') {
        final csrf = await _call(
          client,
          base,
          'GET',
          'api/csrf',
          authorization,
          const {},
          null,
        );
        _check(csrf, login: false, ok: 200);
        final token = _decode(csrf);
        if (token is! Map ||
            token['headerName'] is! String ||
            token['token'] is! String) {
          throw _invalidResponse;
        }
        headers[token['headerName'] as String] = token['token'] as String;
        if (csrf.cookies.isNotEmpty) {
          headers[HttpHeaders.cookieHeader] = csrf.cookies
              .map((cookie) => '${cookie.name}=${cookie.value}')
              .join('; ');
        }
      }
      final response = await _call(
        client,
        base,
        method,
        path,
        authorization,
        headers,
        body,
      );
      if (method == 'POST' && path == 'api/users' && response.status == 409) {
        throw const AuthException(
          'Já existe uma conta com este utilizador.',
          definitelyRejected: true,
        );
      }
      if (method == 'POST' &&
          path == 'api/stock/movements' &&
          response.status == 400) {
        throw const AuthException(
          'Movimento recusado. Verifique os dados e o stock disponível.',
          definitelyRejected: true,
        );
      }
      _check(response, login: login, ok: method == 'POST' ? 201 : 200);
      return _decode(response);
    } on AuthException {
      rethrow;
    } on FormatException {
      throw _invalidResponse;
    } catch (_) {
      throw const AuthException(
        'Não foi possível contactar o servidor. Verifique a ligação.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
