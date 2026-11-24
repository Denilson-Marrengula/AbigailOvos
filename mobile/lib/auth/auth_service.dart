import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'activity_report.dart';
export 'activity_report.dart';

class AuthSession {
  const AuthSession({
    required this.username,
    required this.roles,
    this.mustChangePassword = false,
  });
  final String username;
  final List<String> roles;
  final bool mustChangePassword;
  bool get isAdmin => roles.contains('ROLE_ADMIN');
}

abstract interface class AuthService {
  Future<AuthSession> login(String username, String password);
  Future<List<Product>> products();
  Future<void> createProduct(String name, String unit, String price);
  Future<void> updateProduct(String id, String name, String unit, String price);
  Future<void> setProductActive(String id, bool active);
  Future<void> setMinimumStock(String id, String? quantity);
  Future<List<Customer>> customers();
  Future<Customer> createCustomer(String name, String? phone);
  Future<Customer> updateCustomer(String id, String name, String? phone);
  Future<StockBalance> stockBalance(String productId);
  Future<void> createStockMovement(Map<String, dynamic> request);
  Future<List<SaleRecord>> sales();
  Future<SaleSearchPage> searchSales({
    int page = 0,
    int size = 20,
    String? customer,
    String? product,
    String? seller,
    String state = 'ALL',
    DateTime? from,
    DateTime? to,
  });
  Future<SalesReport> salesReport({DateTime? from, DateTime? to});
  Future<ActivityReport> activityReport({
    required DateTime from,
    required DateTime to,
  });
  Future<List<AuditRecord>> auditEvents({int page = 0, int size = 30});
  Future<void> createSale(Map<String, dynamic> request);
  Future<void> changeSale(
    String id,
    String action, {
    PaymentMethod? paymentMethod,
  });
  Future<List<SellerAccount>> sellers();
  Future<void> createSeller(
    String username,
    String password,
    String name,
    String? phone,
  );
  Future<void> updateSeller(String id, String name, String? phone);
  Future<TemporarySellerPassword> resetSellerPassword(String id);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<void> setSellerEnabled(String id, bool enabled);
  Future<void> deleteSeller(String id);
  Future<void> logout();
}

class TemporarySellerPassword {
  const TemporarySellerPassword({required this.value, required this.expiresAt});
  final String value;
  final DateTime expiresAt;
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
    this.unknownDeliveredDates = 0,
    this.unknownPaidDates = 0,
    this.unknownCancelledDates = 0,
    this.periodStart,
    this.periodEnd,
    this.eventDatesSupported = true,
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
  final int unknownDeliveredDates;
  final int unknownPaidDates;
  final int unknownCancelledDates;
  final String? periodStart;
  final String? periodEnd;
  final bool eventDatesSupported;
}

class SaleSearchPage {
  const SaleSearchPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });
  final List<SaleRecord> items;
  final int page;
  final bool hasMore;
}

class AuditRecord {
  const AuditRecord({
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.detail,
    required this.occurredAt,
  });
  final String actor;
  final String action;
  final String targetType;
  final String targetId;
  final String detail;
  final DateTime occurredAt;
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

enum PaymentMethod {
  emola('EMOLA', 'e-Mola'),
  mpesa('MPESA', 'M-Pesa'),
  bank('BANK', 'Banco'),
  cash('CASH', 'Dinheiro');

  const PaymentMethod(this.code, this.label);
  final String code;
  final String label;
}

String paymentMethodLabel(String? code) {
  if (code == null) return 'Não informado';
  for (final method in PaymentMethod.values) {
    if (method.code == code) return method.label;
  }
  return 'Desconhecido';
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
    this.paymentMethod,
  });
  final String id;
  final String customerName;
  final String seller;
  final String delivery;
  final String payment;
  final String? paymentMethod;
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
    this.availableText,
  });
  final num physical;
  final num reserved;
  final num available;
  final String? availableText;
}

class Product {
  const Product({
    this.id = '',
    required this.name,
    required this.unit,
    required this.price,
    this.active = true,
    this.minimumStock,
    this.minimumStockSupported = true,
  });
  final String id;
  final String name;
  final String unit;
  final String price;
  final bool active;
  final String? minimumStock;
  final bool minimumStockSupported;
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
    this.code,
  });
  final String message;

  final bool sessionExpired;
  final bool definitelyRejected;
  final String? code;
}

class _RawResponse {
  const _RawResponse(this.status, this.text, this.cookies);
  final int status;
  final String text;
  final List<Cookie> cookies;
}

class HttpAuthService implements AuthService {
  HttpAuthService(
    this.baseUrl, {
    this.developmentCertificate = '',
    this.sessionMode = true,
  }) : _readTimeout = const Duration(seconds: 90),
       _writeTimeout = const Duration(seconds: 15);

  @visibleForTesting
  HttpAuthService.withTimeoutsForTesting(
    this.baseUrl, {
    this.developmentCertificate = '',
    this.sessionMode = true,
    required Duration readTimeout,
    required Duration writeTimeout,
  }) : assert(readTimeout > Duration.zero),
       assert(writeTimeout > Duration.zero),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout;

  final String baseUrl;
  final String developmentCertificate;
  final Duration _readTimeout;
  final Duration _writeTimeout;

  /// `false` exists only for isolated compatibility tests against the old API.
  final bool sessionMode;
  String? _authorization;
  AuthSession? _session;
  int _generation = 0;
  static const _connectionTimeout = Duration(seconds: 15);
  static const _invalidResponse = AuthException(
    'Resposta inválida do servidor.',
  );

  @override
  Future<AuthSession> login(String username, String password) async {
    final previous = _authorization;
    _clearAuthentication();
    final generation = _generation;
    if (!sessionMode && !kDebugMode) {
      throw const AuthException(
        'Este modo de autenticação não está disponível nesta versão.',
      );
    }
    if (sessionMode && previous != null) {
      await _revoke(previous);
      if (generation != _generation) {
        throw const AuthException(
          'A sessão mudou. Inicie sessão novamente.',
          sessionExpired: true,
        );
      }
    }
    final basic = sessionMode
        ? null
        : 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    final data = sessionMode
        ? await _send(
            'POST',
            'api/auth/login',
            null,
            body: {'username': username, 'password': password},
            login: true,
            okStatus: 200,
          )
        : await _send('GET', 'api/me', basic, login: true);
    if (data is! Map<String, dynamic> ||
        data['username'] is! String ||
        (data['username'] as String).isEmpty ||
        (data['mustChangePassword'] != null &&
            data['mustChangePassword'] is! bool) ||
        data['roles'] is! List) {
      throw _invalidResponse;
    }
    final roles = (data['roles'] as List).whereType<String>().toList();
    if (!roles.contains('ROLE_ADMIN') && !roles.contains('ROLE_SELLER')) {
      throw const AuthException('Esta conta não tem um perfil autorizado.');
    }
    String authorization;
    if (sessionMode) {
      final token = data['token'];
      final expiresAt = data['expiresAt'];
      if (token is! String ||
          !_validSessionToken(token) ||
          expiresAt is! String ||
          DateTime.tryParse(expiresAt) == null) {
        throw _invalidResponse;
      }
      authorization = 'Bearer $token';
    } else {
      authorization = basic!;
    }
    if (generation != _generation) {
      throw const AuthException(
        'A sessão mudou. Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    final session = AuthSession(
      username: data['username'] as String,
      roles: roles,
      mustChangePassword: data['mustChangePassword'] == true,
    );
    _authorization = authorization;
    _session = session;
    return session;
  }

  @override
  Future<void> logout() async {
    final previous = _authorization;
    _clearAuthentication();
    if (!sessionMode || previous == null) return;
    await _revoke(previous);
  }

  Future<void> _revoke(String previous) async {
    try {
      await _send('POST', 'api/auth/logout', previous, okStatus: 204);
    } on AuthException catch (error) {
      if (!error.sessionExpired) rethrow;
    }
  }

  void _clearAuthentication() {
    _generation++;
    _authorization = null;
    _session = null;
  }

  static bool _validSessionToken(String token) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) return false;
    try {
      final bytes = base64Url.decode(base64Url.normalize(token));
      return bytes.length == 32 &&
          base64UrlEncode(bytes).replaceAll('=', '') == token;
    } on FormatException {
      return false;
    }
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
          item['price'] is! num ||
          (item['minimumStockText'] != null &&
              item['minimumStockText'] is! String)) {
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
        minimumStock: item['minimumStockText'] as String?,
        minimumStockSupported: item.containsKey('minimumStockText'),
      );
    }).toList();
  }

  @override
  Future<void> createProduct(String name, String unit, String price) async {
    await _send(
      'POST',
      'api/products',
      _requireAuthorization(),
      body: {'name': name, 'unit': unit, 'price': price},
    );
  }

  @override
  Future<void> updateProduct(
    String id,
    String name,
    String unit,
    String price,
  ) async {
    await _send(
      'PUT',
      'api/products/${Uri.encodeComponent(id)}',
      _requireAuthorization(),
      body: {'name': name, 'unit': unit, 'price': price},
    );
  }

  @override
  Future<void> setProductActive(String id, bool active) async {
    await _send(
      'PATCH',
      'api/products/${Uri.encodeComponent(id)}/status',
      _requireAuthorization(),
      body: {'active': active},
    );
  }

  @override
  Future<void> setMinimumStock(String id, String? quantity) async {
    await _send(
      quantity == null ? 'DELETE' : 'PUT',
      'api/products/${Uri.encodeComponent(id)}/minimum-stock',
      _requireAuthorization(),
      body: quantity == null ? null : {'minimumStock': quantity},
    );
  }

  @override
  Future<List<Customer>> customers() async {
    final data = await _send('GET', 'api/customers', _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    return data.map(_customerFrom).toList();
  }

  @override
  Future<Customer> createCustomer(String name, String? phone) async {
    await _requireSalesCapabilities(customerPhone: true);
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
  Future<Customer> updateCustomer(String id, String name, String? phone) async {
    await _requireSalesCapabilities(customerPhone: true);
    final data = await _send(
      'PUT',
      'api/customers/${Uri.encodeComponent(id)}',
      _requireAuthorization(),
      body: {'name': name, 'phone': phone},
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
        data['available'] is! num ||
        (data['availableText'] != null && data['availableText'] is! String)) {
      throw _invalidResponse;
    }
    return StockBalance(
      physical: data['quantity'] as num,
      reserved: data['reserved'] as num,
      available: data['available'] as num,
      availableText: data['availableText'] as String?,
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
    await _requireSalesCapabilities();
    final session = _session;
    if (session == null) {
      throw const AuthException(
        'Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    final data = await _send('GET', 'api/sales', _requireAuthorization());
    if (!identical(session, _session)) {
      throw const AuthException(
        'A sessão mudou. Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    if (data is! List) throw _invalidResponse;
    return data.map((item) => _saleFrom(item, session)).toList();
  }

  SaleRecord _saleFrom(dynamic item, AuthSession session) {
    if (item is! Map ||
        item['id'] is! String ||
        item['customerName'] is! String ||
        item['seller'] is! String ||
        item['deliveryStatus'] is! String ||
        item['paymentStatus'] is! String ||
        (item['paymentMethod'] != null && item['paymentMethod'] is! String) ||
        item['total'] is! num ||
        (item['totalText'] != null && item['totalText'] is! String) ||
        item['items'] is! List ||
        item['createdAt'] is! String ||
        DateTime.tryParse(item['createdAt'] as String) == null) {
      throw _invalidResponse;
    }
    if (!session.isAdmin && item['seller'] != session.username) {
      throw const AuthException(
        'O servidor devolveu operações de outro vendedor. A lista não será apresentada.',
      );
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
      paymentMethod: item['paymentMethod'] as String?,
      total: item['total'],
      totalText: item['totalText'] as String?,
      items: lines,
      createdAt: DateTime.parse(item['createdAt'] as String),
    );
  }

  @override
  Future<SaleSearchPage> searchSales({
    int page = 0,
    int size = 20,
    String? customer,
    String? product,
    String? seller,
    String state = 'ALL',
    DateTime? from,
    DateTime? to,
  }) async {
    await _requireSalesCapabilities();
    final session = _session;
    if (session == null) {
      throw const AuthException(
        'Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
      'state': state,
      if (customer != null && customer.trim().isNotEmpty)
        'customer': customer.trim(),
      if (product != null && product.trim().isNotEmpty)
        'product': product.trim(),
      if (seller != null && seller.trim().isNotEmpty) 'seller': seller.trim(),
      if (from != null) 'from': _dateOnly(from),
      if (to != null) 'to': _dateOnly(to),
    };
    final path = Uri(
      path: 'api/sales/search',
      queryParameters: params,
    ).toString();
    final data = await _send('GET', path, _requireAuthorization());
    if (!identical(session, _session)) {
      throw const AuthException(
        'A sessão mudou. Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    if (data is! Map ||
        data['items'] is! List ||
        data['page'] != page ||
        data['hasMore'] is! bool) {
      throw _invalidResponse;
    }
    return SaleSearchPage(
      items: (data['items'] as List)
          .map((item) => _saleFrom(item, session))
          .toList(),
      page: page,
      hasMore: data['hasMore'] as bool,
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Future<ActivityReport> activityReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final session = _session;
    if (session == null) {
      throw const AuthException(
        'Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    if (!session.isAdmin) {
      throw const AuthException(
        'Não tem permissão para esta operação.',
        definitelyRejected: true,
      );
    }
    final start = _dateOnly(from);
    final end = _dateOnly(to);
    final path = Uri(
      path: 'api/reports/activity',
      queryParameters: {'from': start, 'to': end},
    ).toString();
    final data = await _send('GET', path, _requireAuthorization());
    if (!identical(session, _session)) {
      throw const AuthException(
        'A sessão mudou. Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    try {
      return ActivityReport.fromJson(data, from: start, to: end);
    } on FormatException {
      throw _invalidResponse;
    }
  }

  @override
  Future<SalesReport> salesReport({DateTime? from, DateTime? to}) async {
    if ((from == null) != (to == null)) {
      throw const AuthException('Indique o início e o fim do período.');
    }
    final params = <String, String>{
      if (from != null) 'from': _dateOnly(from),
      if (to != null) 'to': _dateOnly(to),
    };
    final data = await _send(
      'GET',
      params.isEmpty
          ? 'api/reports/sales'
          : Uri(path: 'api/reports/sales', queryParameters: params).toString(),
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
        (data['periodStart'] != null && data['periodStart'] is! String) ||
        (data['periodEnd'] != null && data['periodEnd'] is! String) ||
        data['sellers'] is! List) {
      throw _invalidResponse;
    }
    // Older servers may ignore query parameters. Never show all-time figures as a selected period.
    if (from != null &&
        (data['periodStart'] != _dateOnly(from) ||
            data['periodEnd'] != _dateOnly(to!) ||
            data['timeZone'] != 'Africa/Maputo' ||
            data['unknownDeliveredDates'] is! int ||
            data['unknownPaidDates'] is! int ||
            data['unknownCancelledDates'] is! int)) {
      throw const AuthException(
        'O servidor não suporta relatórios por período com datas de eventos.',
      );
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
      unknownDeliveredDates: data['unknownDeliveredDates'] is int
          ? data['unknownDeliveredDates']
          : 0,
      unknownPaidDates: data['unknownPaidDates'] is int
          ? data['unknownPaidDates']
          : 0,
      unknownCancelledDates: data['unknownCancelledDates'] is int
          ? data['unknownCancelledDates']
          : 0,
      periodStart: data['periodStart'] as String?,
      periodEnd: data['periodEnd'] as String?,
      eventDatesSupported:
          data['timeZone'] == 'Africa/Maputo' &&
          data['unknownDeliveredDates'] is int &&
          data['unknownPaidDates'] is int &&
          data['unknownCancelledDates'] is int,
    );
  }

  @override
  Future<List<AuditRecord>> auditEvents({int page = 0, int size = 30}) async {
    final path = Uri(
      path: 'api/audit/events',
      queryParameters: {'page': '$page', 'size': '$size'},
    ).toString();
    final data = await _send('GET', path, _requireAuthorization());
    if (data is! List) throw _invalidResponse;
    return data.map((item) {
      if (item is! Map ||
          item['actor'] is! String ||
          item['action'] is! String ||
          item['targetType'] is! String ||
          item['targetId'] is! String ||
          item['detail'] is! String ||
          item['occurredAt'] is! String ||
          DateTime.tryParse(item['occurredAt'] as String) == null) {
        throw _invalidResponse;
      }
      return AuditRecord(
        actor: item['actor'],
        action: item['action'],
        targetType: item['targetType'],
        targetId: item['targetId'],
        detail: item['detail'],
        occurredAt: DateTime.parse(item['occurredAt']),
      );
    }).toList();
  }

  @override
  Future<void> createSale(Map<String, dynamic> request) async {
    await _requireSalesCapabilities(
      paymentMethods: request['paid'] == true,
      customerPhone: request['customer'] != null,
    );
    await _send('POST', 'api/sales', _requireAuthorization(), body: request);
  }

  Future<void> _requireSalesCapabilities({
    bool paymentMethods = false,
    bool customerPhone = false,
  }) async {
    final authorization = _requireAuthorization();
    final session = _session;
    if (session == null) {
      throw const AuthException(
        'Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    dynamic capabilities;
    try {
      capabilities = await _send(
        'GET',
        'api/sales/capabilities',
        authorization,
      );
    } on AuthException catch (error) {
      if (error.sessionExpired) rethrow;
    }
    if (!identical(session, _session) || _authorization != authorization) {
      throw const AuthException(
        'A sessão mudou. Inicie sessão novamente.',
        sessionExpired: true,
      );
    }
    if (capabilities is! Map ||
        capabilities['sellerSalesIsolation'] != true ||
        capabilities['adminSaleAssistance'] != true) {
      throw const AuthException(
        'Não foi possível confirmar as permissões de vendas neste servidor. Atualize o servidor antes de usar as vendas.',
        definitelyRejected: true,
      );
    }
    if (paymentMethods && capabilities['paymentMethods'] != true) {
      throw const AuthException(
        'Não foi possível confirmar que o servidor guarda o meio de pagamento. Nenhum pagamento foi enviado.',
        definitelyRejected: true,
      );
    }
    if (customerPhone && capabilities['customerPhoneUnique'] != true) {
      throw const AuthException(
        'Não foi possível confirmar a proteção contra telefones duplicados. Atualize o servidor antes de guardar clientes.',
        definitelyRejected: true,
      );
    }
  }

  @override
  Future<void> changeSale(
    String id,
    String action, {
    PaymentMethod? paymentMethod,
  }) async {
    if (!const {'deliver', 'cancel', 'pay'}.contains(action)) {
      throw _invalidResponse;
    }
    if ((action == 'pay') != (paymentMethod != null)) {
      throw const AuthException(
        'Selecione um meio de pagamento.',
        definitelyRejected: true,
      );
    }
    await _requireSalesCapabilities(paymentMethods: action == 'pay');
    await _send(
      'PATCH',
      'api/sales/${Uri.encodeComponent(id)}/$action',
      _requireAuthorization(),
      body: paymentMethod == null ? null : {'method': paymentMethod.code},
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
  Future<TemporarySellerPassword> resetSellerPassword(String id) async {
    final data = await _send(
      'PATCH',
      'api/users/${Uri.encodeComponent(id)}/password-reset',
      _requireAuthorization(),
    );
    if (data is! Map ||
        data['temporaryPassword'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{32}$')
            .hasMatch(data['temporaryPassword'] as String) ||
        data['expiresAt'] is! String ||
        DateTime.tryParse(data['expiresAt'] as String) == null) {
      throw _invalidResponse;
    }
    return TemporarySellerPassword(
      value: data['temporaryPassword'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _send(
      'PUT',
      'api/account/password',
      _requireAuthorization(),
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    // A successful password change invalidates the server-side session epoch.
    _clearAuthentication();
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

  @override
  Future<void> deleteSeller(String id) async {
    await _send(
      'DELETE',
      'api/users/${Uri.encodeComponent(id)}',
      _requireAuthorization(),
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
    return HttpClient(context: securityContext)
      ..connectionTimeout = _connectionTimeout;
  }

  Future<_RawResponse> _call(
    HttpClient client,
    Uri base,
    String method,
    String path,
    String? authorization,
    Map<String, String> headers,
    Object? body,
  ) async {
    // Use one deadline for each request, including the response body. A GET,
    // including the CSRF preflight, can wake a sleeping service. Never retry a
    // write automatically: a timeout does not prove it was not applied.
    final timeout = method == 'GET' ? _readTimeout : _writeTimeout;
    final elapsed = Stopwatch()..start();
    Duration remaining() {
      final time = timeout - elapsed.elapsed;
      return time > Duration.zero ? time : Duration.zero;
    }

    final request = await client
        .openUrl(method, base.resolve(path))
        .timeout(remaining());
    request.followRedirects = false;
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(remaining());
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(remaining());
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
      case 429:
        throw const AuthException(
          'Muitas tentativas de acesso nesta rede. Aguarde alguns minutos e tente novamente.',
          definitelyRejected: true,
        );
      case 502:
      case 503:
      case 504:
        throw const AuthException(
          'O servidor está temporariamente indisponível. Verifique a ligação.',
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
    String? authorization, {
    Object? body,
    bool login = false,
    int? okStatus,
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
        _check(csrf, login: login, ok: 200);
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
      if (method == 'GET' && path.startsWith('api/reports/activity?')) {
        if (response.status == 413) {
          throw const AuthException(
            'Relatório demasiado grande para apresentar ou imprimir integralmente. É necessária uma consulta paginada.',
          );
        }
        if (response.status == 404) {
          throw const AuthException(
            'O servidor ainda não suporta os relatórios detalhados.',
          );
        }
      }
      if (method == 'POST' && path == 'api/users' && response.status == 409) {
        throw const AuthException(
          'Já existe uma conta com este utilizador.',
          definitelyRejected: true,
        );
      }
      if (response.status == 409 &&
          ((method == 'POST' && path == 'api/sales') ||
              (method == 'PUT' && path.startsWith('api/customers/')))) {
        dynamic conflict;
        try {
          conflict = _decode(response);
        } on FormatException {
          /* Resposta genérica. */
        }
        if (conflict is Map && conflict['code'] == 'CUSTOMER_PHONE_EXISTS') {
          throw const AuthException(
            'Este telefone já pertence a outro cliente. Atualize a lista e selecione o cliente existente.',
            definitelyRejected: true,
            code: 'CUSTOMER_PHONE_EXISTS',
          );
        }
      }
      if (method == 'POST' &&
          path == 'api/stock/movements' &&
          response.status == 400) {
        throw const AuthException(
          'Movimento recusado. Verifique os dados e o stock disponível.',
          definitelyRejected: true,
        );
      }
      _check(
        response,
        login: login,
        ok:
            okStatus ??
            switch (method) {
              'POST' => 201,
              'DELETE' => 204,
              _ => 200,
            },
      );
      return _decode(response);
    } on AuthException {
      rethrow;
    } on FormatException {
      throw _invalidResponse;
    } on TimeoutException {
      throw const AuthException(
        'O servidor demorou demasiado a responder. Verifique a ligação.',
      );
    } catch (_) {
      throw const AuthException(
        'Não foi possível contactar o servidor. Verifique a ligação.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
