import 'dart:async';
import 'dart:convert';

import 'package:abigailovos/auth/auth_service.dart';
import 'package:abigailovos/admin/admin_shell.dart';
import 'package:abigailovos/admin/sales_report_pdf.dart';
import 'package:abigailovos/auth/login_page.dart';
import 'package:abigailovos/design/app_logo.dart';
import 'package:abigailovos/design/app_navigation_drawer.dart';
import 'package:abigailovos/design/app_theme.dart';
import 'package:abigailovos/design/overview_widgets.dart';
import 'package:abigailovos/main.dart';
import 'package:abigailovos/seller/seller_widgets.dart';
import 'package:abigailovos/seller/customers_page.dart';
import 'package:abigailovos/seller/sales_page.dart';
import 'package:abigailovos/seller/seller_controller.dart';
import 'package:abigailovos/seller/stock_movement_page.dart';
import 'package:abigailovos/seller/stock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

class FakeAuth implements AuthService {
  bool admin = false;
  bool logoutFails = false;
  String username = 'ana';
  bool failProducts = false;
  bool expired = false;
  bool failReports = false;
  bool failPeriodReports = false;
  bool reportEventDatesSupported = true;
  int reportUnknownDeliveredDates = 0;
  int reportUnknownPaidDates = 0;
  int reportUnknownCancelledDates = 0;
  bool failActivityReports = false;
  ActivityReport? activityData;
  DateTime? activityFrom;
  DateTime? activityTo;
  bool loseProductResponse = false;
  bool loseCustomerUpdateResponse = false;
  int salesCalls = 0;
  DateTime? reportFrom;
  DateTime? reportTo;
  final List<AuditRecord> auditRows = [];
  Map<String, dynamic>? lastSaleRequest;
  String? lastSaleAction;
  PaymentMethod? lastPaymentMethod;
  bool loseSaleActionResponse = false;
  bool loseSaleCreateResponse = false;
  bool rejectSaleCreateBeforeSend = false;
  Map<String, dynamic>? lastStockRequest;
  bool loseStockResponseOnce = false;
  bool rejectStockBeforeSend = false;
  final Set<String> _stockOperationIds = {};
  num stockQuantity = 12;
  final List<SellerAccount> _sellers = [];
  final Map<String, String> _passwords = {};
  final Set<String> _mustChange = {};
  @override
  Future<List<SellerAccount>> sellers() async => List.of(_sellers);
  @override
  Future<void> createSeller(
    String username,
    String password,
    String name,
    String? phone,
  ) async {
    _passwords[username] = password;
    _mustChange.add(username);
    _sellers.add(
      SellerAccount(
        id: '${_sellers.length + 1}',
        username: username,
        displayName: name,
        phone: phone,
        enabled: true,
      ),
    );
  }

  @override
  Future<void> updateSeller(String id, String name, String? phone) async {
    final i = _sellers.indexWhere((s) => s.id == id);
    final s = _sellers[i];
    _sellers[i] = SellerAccount(
      id: id,
      username: s.username,
      displayName: name,
      phone: phone,
      enabled: s.enabled,
    );
  }

  @override
  Future<void> setSellerEnabled(String id, bool enabled) async {
    final i = _sellers.indexWhere((s) => s.id == id);
    final s = _sellers[i];
    _sellers[i] = SellerAccount(
      id: id,
      username: s.username,
      displayName: s.displayName,
      phone: s.phone,
      enabled: enabled,
    );
  }

  @override
  Future<void> deleteSeller(String id) async {
    _sellers.removeWhere((seller) => seller.id == id);
  }

  @override
  Future<TemporarySellerPassword> resetSellerPassword(String id) async {
    final seller = _sellers.firstWhere((account) => account.id == id);
    if (!admin || !seller.enabled) {
      throw const AuthException('Sem permissão.', definitelyRejected: true);
    }
    const temporary = '0123456789abcdefghijklmnopqrstuv';
    _passwords[seller.username] = temporary;
    _mustChange.add(seller.username);
    return TemporarySellerPassword(
      value: temporary,
      expiresAt: DateTime.utc(2026, 11, 15),
    );
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (_passwords[username] != currentPassword ||
        !_mustChange.contains(username)) {
      throw const AuthException(
        'Palavra-passe inválida.',
        definitelyRejected: true,
      );
    }
    _passwords[username] = newPassword;
    _mustChange.remove(username);
  }

  final List<SaleRecord> _sales = [];
  @override
  Future<List<SaleRecord>> sales() async {
    salesCalls++;
    return _sales.where((sale) => admin || sale.seller == username).toList();
  }

  @override
  Future<SalesReport> salesReport({DateTime? from, DateTime? to}) async {
    if (failReports) throw const AuthException('Relatório indisponível');
    if (from != null && failPeriodReports) {
      throw const AuthException('Servidor não suporta o período.');
    }
    reportFrom = from;
    reportTo = to;
    String day(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final active = _sales.where((s) => s.delivery != 'CANCELLED').toList();
    final delivered = active.where((s) => s.delivery == 'DELIVERED').toList();
    final paid = active.where((s) => s.payment == 'PAID').toList();
    final pending = active.where((s) => s.payment == 'PENDING').toList();
    String total(List<SaleRecord> rows) => rows
        .fold<num>(0, (value, sale) => value + sale.total)
        .toStringAsFixed(2);
    final names = delivered.map((s) => s.seller).toSet().toList()..sort();
    return SalesReport(
      pendingOrders: active.where((s) => s.delivery == 'PENDING').length,
      deliveredSales: delivered.length,
      cancelledOperations: _sales
          .where((s) => s.delivery == 'CANCELLED')
          .length,
      pendingPayments: pending.length,
      markedPaid: paid.length,
      deliveredAmount: total(delivered),
      markedPaidAmount: total(paid),
      pendingPaymentAmount: total(pending),
      sellers: names.map((name) {
        final rows = delivered.where((s) => s.seller == name).toList();
        return SellerPerformance(
          seller: name,
          deliveredCount: rows.length,
          deliveredAmount: total(rows),
        );
      }).toList(),
      unknownDeliveredDates: reportUnknownDeliveredDates,
      unknownPaidDates: reportUnknownPaidDates,
      unknownCancelledDates: reportUnknownCancelledDates,
      eventDatesSupported: reportEventDatesSupported,
      periodStart: from == null ? null : day(from),
      periodEnd: to == null ? null : day(to),
    );
  }

  @override
  Future<ActivityReport> activityReport({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!admin) {
      throw const AuthException('Sem permissão.', definitelyRejected: true);
    }
    if (failActivityReports) {
      throw const AuthException('Relatório indisponível.');
    }
    activityFrom = from;
    activityTo = to;
    String day(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final data = activityData;
    return ActivityReport(
      periodStart: day(from),
      periodEnd: day(to),
      queriedAt: data?.queriedAt ?? DateTime.utc(2026, 11, 23),
      unknownDeliveredDates: data?.unknownDeliveredDates ?? 0,
      unknownPaidDates: data?.unknownPaidDates ?? 0,
      deliveredAmount: data?.deliveredAmount ?? '0.00',
      debtAmount: data?.debtAmount ?? '0.00',
      pendingOrderAmount: data?.pendingOrderAmount ?? '0.00',
      paidAmount: data?.paidAmount ?? '0.00',
      deliveredCustomers: data?.deliveredCustomers ?? const [],
      debtCustomers: data?.debtCustomers ?? const [],
      pendingOrders: data?.pendingOrders ?? const [],
      paymentMethods: data?.paymentMethods ?? const [],
      payments: data?.payments ?? const [],
      sellers: data?.sellers ?? const [],
      deliveries: data?.deliveries ?? const [],
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
    final rows = (await sales()).where((sale) {
      if (customer != null &&
          customer.trim().isNotEmpty &&
          !sale.customerName.toLowerCase().contains(customer.toLowerCase())) {
        return false;
      }
      if (product != null &&
          product.trim().isNotEmpty &&
          !sale.items.any(
            (item) => item.toLowerCase().contains(product.toLowerCase()),
          )) {
        return false;
      }
      if (seller != null && seller.trim().isNotEmpty && sale.seller != seller) {
        return false;
      }
      if (from != null &&
          sale.createdAt != null &&
          sale.createdAt!.isBefore(from)) {
        return false;
      }
      if (to != null &&
          sale.createdAt != null &&
          !sale.createdAt!.isBefore(to.add(const Duration(days: 1)))) {
        return false;
      }
      return switch (state) {
        'PENDING_DELIVERY' => sale.delivery == 'PENDING',
        'PENDING_PAYMENT' =>
          sale.delivery != 'CANCELLED' && sale.payment == 'PENDING',
        'DELIVERED' => sale.delivery == 'DELIVERED',
        'CANCELLED' => sale.delivery == 'CANCELLED',
        _ => true,
      };
    }).toList();
    final start = page * size;
    final items = start >= rows.length
        ? <SaleRecord>[]
        : rows.skip(start).take(size).toList();
    return SaleSearchPage(
      items: items,
      page: page,
      hasMore: start + size < rows.length,
    );
  }

  @override
  Future<List<AuditRecord>> auditEvents({int page = 0, int size = 30}) async =>
      auditRows.skip(page * size).take(size).toList();

  @override
  Future<void> setMinimumStock(String id, String? quantity) async {
    final index = _products.indexWhere((p) => p.id == id);
    final product = _products[index];
    _products[index] = Product(
      id: product.id,
      name: product.name,
      unit: product.unit,
      price: product.price,
      active: product.active,
      minimumStock: quantity,
    );
  }

  @override
  Future<void> createSale(Map<String, dynamic> request) async {
    if (admin) {
      throw const AuthException('Sem permissão.', definitelyRejected: true);
    }
    lastSaleRequest = request;
    if (rejectSaleCreateBeforeSend) {
      throw const AuthException(
        'Servidor incompatível.',
        definitelyRejected: true,
      );
    }
    if (_sales.any((sale) => sale.id == request['id'])) return;
    final newCustomer = request['customer'] as Map<String, dynamic>?;
    if (newCustomer != null) {
      _checkCustomerPhone(newCustomer['phone'] as String?);
      _customers.add(
        Customer(
          id: '2',
          name: newCustomer['name'] as String,
          phone: newCustomer['phone'] as String?,
        ),
      );
    }
    _sales.add(
      SaleRecord(
        id: request['id'] as String,
        customerName: newCustomer?['name'] as String? ?? 'Maria Chongo',
        seller: username,
        delivery: request['deliverNow'] == true ? 'DELIVERED' : 'PENDING',
        payment: request['paid'] == true ? 'PAID' : 'PENDING',
        paymentMethod: request['paymentMethod'] as String?,
        total: 100,
        items: const ['1 bandeja · Ovos'],
      ),
    );
    if (loseSaleCreateResponse) {
      loseSaleCreateResponse = false;
      throw const AuthException('Ligação interrompida.');
    }
  }

  @override
  Future<void> changeSale(
    String id,
    String action, {
    PaymentMethod? paymentMethod,
  }) async {
    final index = _sales.indexWhere((sale) => sale.id == id);
    if (index < 0 ||
        (!admin && _sales[index].seller != username) ||
        (admin && action == 'cancel') ||
        !const {'deliver', 'pay', 'cancel'}.contains(action)) {
      throw const AuthException('Sem permissão.', definitelyRejected: true);
    }
    final sale = _sales[index];
    if ((action == 'deliver' && sale.delivery != 'PENDING') ||
        (action == 'pay' &&
            (sale.delivery == 'CANCELLED' ||
                sale.payment != 'PENDING' ||
                paymentMethod == null)) ||
        (action == 'cancel' &&
            (sale.delivery != 'PENDING' || sale.payment != 'PENDING'))) {
      throw const AuthException(
        'Operação não permitida.',
        definitelyRejected: true,
      );
    }
    lastSaleAction = action;
    lastPaymentMethod = paymentMethod;
    _sales[index] = SaleRecord(
      id: sale.id,
      customerName: sale.customerName,
      seller: sale.seller,
      delivery: action == 'deliver'
          ? 'DELIVERED'
          : action == 'cancel'
          ? 'CANCELLED'
          : sale.delivery,
      payment: action == 'pay' ? 'PAID' : sale.payment,
      paymentMethod: action == 'pay' ? paymentMethod?.code : sale.paymentMethod,
      total: sale.total,
      totalText: sale.totalText,
      items: sale.items,
      createdAt: sale.createdAt,
    );
    if (loseSaleActionResponse) {
      loseSaleActionResponse = false;
      throw const AuthException('Ligação interrompida.');
    }
  }

  final List<Customer> _customers = [
    const Customer(id: '1', name: 'Maria Chongo', phone: '84 123 4567'),
  ];

  @override
  Future<void> logout() async {
    if (logoutFails) throw const AuthException('Ligação interrompida.');
  }

  @override
  Future<AuthSession> login(String username, String password) async {
    if ((_passwords[username] ?? 'correta') != password) {
      throw const AuthException('Dados inválidos');
    }
    this.username = username;
    return AuthSession(
      username: username,
      roles: [admin ? 'ROLE_ADMIN' : 'ROLE_SELLER'],
      mustChangePassword: _mustChange.contains(username),
    );
  }

  final List<Product> _products = [
    const Product(id: 'p1', name: 'Ovos', unit: 'bandeja', price: '100.0'),
  ];

  @override
  Future<List<Product>> products() async {
    if (expired) {
      throw const AuthException('Sessão terminada', sessionExpired: true);
    }
    if (failProducts) throw const AuthException('Falha ao carregar produtos');
    return _products.where((product) => admin || product.active).toList();
  }

  @override
  Future<void> createProduct(String name, String unit, String price) async {
    _products.add(
      Product(
        id: 'p${_products.length + 1}',
        name: name,
        unit: unit,
        price: price,
      ),
    );
    if (loseProductResponse) {
      loseProductResponse = false;
      throw const AuthException('Ligação interrompida.');
    }
  }

  @override
  Future<void> updateProduct(
    String id,
    String name,
    String unit,
    String price,
  ) async {
    final index = _products.indexWhere((product) => product.id == id);
    _products[index] = Product(
      id: id,
      name: name,
      unit: unit,
      price: price,
      active: _products[index].active,
      minimumStock: _products[index].minimumStock,
    );
  }

  @override
  Future<void> setProductActive(String id, bool active) async {
    final index = _products.indexWhere((product) => product.id == id);
    final product = _products[index];
    _products[index] = Product(
      id: id,
      name: product.name,
      unit: product.unit,
      price: product.price,
      active: active,
      minimumStock: product.minimumStock,
    );
  }

  @override
  Future<List<Customer>> customers() async => List.of(_customers);

  @override
  Future<Customer> createCustomer(String name, String? phone) async {
    _checkCustomerPhone(phone);
    final customer = Customer(
      id: '${_customers.length + 1}',
      name: name,
      phone: phone,
    );
    _customers.add(customer);
    return customer;
  }

  @override
  Future<Customer> updateCustomer(String id, String name, String? phone) async {
    _checkCustomerPhone(phone, exceptId: id);
    final index = _customers.indexWhere((customer) => customer.id == id);
    final customer = Customer(
      id: id,
      name: name,
      phone: phone,
      createdAt: _customers[index].createdAt,
    );
    _customers[index] = customer;
    if (loseCustomerUpdateResponse) {
      loseCustomerUpdateResponse = false;
      throw const AuthException('Ligação interrompida.');
    }
    return customer;
  }

  void _checkCustomerPhone(String? phone, {String? exceptId}) {
    final key = customerPhoneKey(phone);
    if (key == null) {
      throw const AuthException('Telefone inválido.', definitelyRejected: true);
    }
    if (_customers.any(
      (customer) =>
          customer.id != exceptId && customerPhoneKey(customer.phone) == key,
    )) {
      throw const AuthException(
        'Telefone já registado.',
        definitelyRejected: true,
        code: 'CUSTOMER_PHONE_EXISTS',
      );
    }
  }

  @override
  Future<StockBalance> stockBalance(String productId) async => StockBalance(
    physical: stockQuantity,
    reserved: 0,
    available: stockQuantity,
    availableText: stockQuantity.toStringAsFixed(2),
  );

  @override
  Future<void> createStockMovement(Map<String, dynamic> request) async {
    lastStockRequest = request;
    if (rejectStockBeforeSend) {
      throw const AuthException(
        'Servidor recusou o pedido.',
        definitelyRejected: true,
      );
    }
    final operationId = request['operationId'] as String;
    if (!_stockOperationIds.add(operationId)) return;
    final amount = num.parse(request['quantity'] as String);
    stockQuantity += request['direction'] == 'INCREASE' ? amount : -amount;
    if (loseStockResponseOnce) {
      loseStockResponseOnce = false;
      throw const AuthException('Ligação interrompida.');
    }
  }
}

class SlowLoginAuth extends FakeAuth {
  final result = Completer<AuthSession>();
  int loginCalls = 0;

  @override
  Future<AuthSession> login(String username, String password) {
    loginCalls++;
    return result.future;
  }
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder _drawerItem(String label) => find.descendant(
  of: find.byType(AppNavigationDrawer),
  matching: find.text(label),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('abertura e login não mostram rótulos de teste', (tester) async {
    await tester.pumpWidget(const AbigailOvosApp());
    expect(find.byType(StartupScreen), findsOneWidget);
    expect(find.text('Iniciar sessão'), findsNothing);
    expect(
      tester
          .widget<Scaffold>(
            find.descendant(
              of: find.byType(StartupScreen),
              matching: find.byType(Scaffold),
            ),
          )
          .backgroundColor,
      AppColors.forest,
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.byType(StartupScreen), findsNothing);
    expect(find.text('Iniciar sessão'), findsOneWidget);
    expect(find.text('AMBIENTE DE TESTE. NÃO USAR DADOS REAIS'), findsNothing);
    expect(
      find.text('Base isolada de teste: não introduza dados reais.'),
      findsNothing,
    );
  });

  testWidgets('login valida e mostra erros', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    expect(find.byType(AppLogo), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Introduza o utilizador.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'errada');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Dados inválidos'), findsOneWidget);
  });

  testWidgets('login informa a espera e impede envios repetidos', (
    tester,
  ) async {
    final auth = SlowLoginAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(
      find.text('A ligar ao servidor. A resposta pode demorar um pouco.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(auth.loginCalls, 1);

    auth.result.completeError(const AuthException('Servidor indisponível.'));
    await tester.pumpAndSettle();
    expect(find.text('Servidor indisponível.'), findsOneWidget);
    expect(
      find.text('A ligar ao servidor. A resposta pode demorar um pouco.'),
      findsNothing,
    );
    expect(find.text('Entrar'), findsOneWidget);
    expect(auth.loginCalls, 1);
  });

  testWidgets(
    'documentos legais estão acessíveis e identificados como rascunho',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: FakeAuth())));
      await tester.ensureVisible(find.text('Política de privacidade'));
      await tester.tap(find.text('Política de privacidade'));
      await tester.pumpAndSettle();
      expect(find.text('Texto em preparação'), findsOneWidget);
      expect(find.textContaining('Não é uma versão final'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Termos e condições'));
      await tester.tap(find.text('Termos e condições'));
      await tester.pumpAndSettle();
      expect(find.text('Texto em preparação'), findsOneWidget);
      expect(find.text('Condições por definir'), findsOneWidget);
    },
  );

  test('tema usa botões retangulares em vez de formato de pílula', () {
    final theme = AppTheme.create(Brightness.light);
    final shape = theme.filledButtonTheme.style!.shape!.resolve({});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(6),
    );
    expect(
      theme.navigationBarTheme.indicatorShape,
      isA<RoundedRectangleBorder>(),
    );
  });

  testWidgets('vendedor consulta produtos, stock e regista cliente', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, vendedor'), findsOneWidget);
    expect(find.text('Perfil: Vendedor'), findsOneWidget);

    expect(_tab('Produtos'), findsNothing);
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Ovos'), findsOneWidget);
    expect(find.textContaining('100.00 MT'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tap(_tab('Clientes'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Chongo'), findsOneWidget);
    expect(find.text('Novo cliente'), findsNothing);
    await tester.tap(_tab('Vendas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova venda'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.'), '1');
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do cliente'),
      'Joana Mabunda',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (obrigatório)'),
      '857654321',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregues'));
    await tester.pumpAndSettle();
    expect(find.text('Joana Mabunda'), findsOneWidget);
    final sentItem = (auth.lastSaleRequest!['items'] as List).single as Map;
    expect(sentItem['quantity'], '1');
    expect(sentItem['expectedUnitPrice'], '100.0');

    await tester.tap(find.byTooltip('Terminar sessão'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sessão'), findsOneWidget);
    expect(find.text('correta'), findsNothing);
  });

  testWidgets('início oferece acesso direto a nova venda', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Visão geral'), findsOneWidget);
    expect(find.text('Nova venda'), findsOneWidget);
    await tester.tap(find.text('Nova venda'));
    await tester.pumpAndSettle();
    expect(find.text('1. Produtos e quantidades'), findsOneWidget);
    expect(find.text('Novo cliente'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Confirmar venda'), findsOneWidget);
  });

  testWidgets('menu lateral do vendedor mantém acessos e saída', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(_drawerItem('Vendedor'), findsOneWidget);
    expect(_drawerItem('Vendedores'), findsNothing);
    expect(_drawerItem('Relatórios'), findsNothing);
    await tester.tap(_drawerItem('Stock'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Ovos'), findsOneWidget);

    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppNavigationDrawer>(find.byType(AppNavigationDrawer))
          .selectedIndex,
      1,
    );
    await tester.tap(_drawerItem('Vendas'));
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    await tester.tap(_drawerItem('Terminar sessão'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sessão'), findsOneWidget);
  });

  testWidgets('menu administrativo mantém opções próprias e funciona em erro', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..admin = true
      ..failReports = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Relatório indisponível'), findsOneWidget);

    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(_drawerItem('Administrador'), findsOneWidget);
    expect(_drawerItem('Vendedores'), findsOneWidget);
    expect(_drawerItem('Relatórios'), findsOneWidget);
    expect(_drawerItem('Vendas'), findsNothing);
    await tester.tap(_drawerItem('Vendedores'));
    await tester.pumpAndSettle();
    expect(find.text('Novo vendedor'), findsOneWidget);
    expect(find.text('Nova venda'), findsNothing);

    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    await tester.tap(_drawerItem('Clientes'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Chongo'), findsOneWidget);
    expect(find.text('Novo cliente'), findsNothing);
  });

  testWidgets('menu lateral adapta-se a ecrã estreito e texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_drawerItem('Relatórios'));
    await tester.tap(_drawerItem('Relatórios'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
  });

  testWidgets('atalho administrativo abre o stock existente', (tester) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil: Administrador'), findsOneWidget);

    final stockShortcut = find.widgetWithText(
      OverviewActionTile,
      'Stock e preços',
    );
    final dashboardScroll = find
        .descendant(
          of: find.byType(AdminDashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      stockShortcut,
      200,
      scrollable: dashboardScroll,
    );
    await tester.tap(stockShortcut);
    await tester.pumpAndSettle();
    expect(find.text('Ovos'), findsOneWidget);
    expect(find.text('Atualizar stock'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets('início adapta-se a ecrã estreito e texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vendedor regista entrada de stock com confirmação', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atualizar stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item de stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ovos · bandeja').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantidade'),
      '3',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Rever movimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rever movimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Stock atualizado.'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(auth.lastStockRequest!['type'], 'ENTRY');
    expect(
      auth.lastStockRequest!['reason'],
      'Entrada de stock (registo automático)',
    );
    expect(auth.lastStockRequest!['quantity'], '3');
    expect(auth.lastStockRequest!['operationId'], isA<String>());
  });

  testWidgets('ajustes, perdas e quebras exigem motivo', (tester) async {
    final auth = FakeAuth();
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshAll();
    await tester.pumpWidget(
      MaterialApp(home: StockMovementPage(controller: controller)),
    );
    await tester.tap(find.text('Item de stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ovos · bandeja').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantidade'),
      '1',
    );
    for (final label in ['Ajuste', 'Perda', 'Quebra']) {
      final typeField = find.byType(DropdownButtonFormField<String>).at(1);
      await tester.ensureVisible(typeField);
      await tester.tap(typeField);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: typeField, matching: find.text(label)),
        findsOneWidget,
      );
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Rever movimento'));
      await tester.tap(find.text('Rever movimento'));
      await tester.pumpAndSettle();
      expect(find.text('Indique o motivo.'), findsOneWidget);
      expect(auth.lastStockRequest, isNull);
    }
  });

  testWidgets(
    'reenvio após falha de comunicação conserva identificador do stock',
    (tester) async {
      final auth = FakeAuth()..loseStockResponseOnce = true;
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
      await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
      await tester.enterText(find.byType(TextFormField).at(1), 'correta');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atualizar stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item de stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ovos · bandeja').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade'),
        '3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Observação (opcional)'),
        'Reposição',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rever movimento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rever movimento'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      final id = auth.lastStockRequest!['operationId'];
      expect(find.textContaining('resultado é desconhecido'), findsOneWidget);
      await tester.ensureVisible(find.text('Repetir envio'));
      await tester.pumpAndSettle();
      auth.rejectStockBeforeSend = true;
      await tester.tap(find.text('Repetir envio'));
      await tester.pumpAndSettle();
      expect(auth.lastStockRequest!['operationId'], id);
      expect(find.text('Repetir envio'), findsOneWidget);
      expect(find.textContaining('resultado é desconhecido'), findsOneWidget);
      expect(auth.stockQuantity, 15);
      auth.rejectStockBeforeSend = false;
      await tester.tap(find.text('Repetir envio'));
      await tester.pumpAndSettle();
      expect(auth.lastStockRequest!['operationId'], id);
      expect(auth.stockQuantity, 15);
      expect(find.text('15'), findsOneWidget);
    },
  );

  testWidgets('avisa sobre cliente possivelmente duplicado durante a venda', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Vendas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do cliente'),
      'Maria Chongo',
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Possível cliente já registado: Maria Chongo'),
      findsOneWidget,
    );
  });

  testWidgets('telefone repetido permite selecionar o cliente existente', (
    tester,
  ) async {
    final auth = FakeAuth();
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshAll();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleFormPage(controller: controller, onExpired: () {}),
      ),
    );
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do cliente'),
      'Outro nome',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (obrigatório)'),
      '+258 84 123 4567',
    );
    await tester.pumpAndSettle();
    expect(find.text('Usar cliente existente: Maria Chongo'), findsOneWidget);
    await tester.tap(find.text('Usar cliente existente: Maria Chongo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.'), '1');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    expect(auth.lastSaleRequest!['customerId'], '1');
    expect(auth.lastSaleRequest!.containsKey('customer'), isFalse);
    expect(auth._customers, hasLength(1));
  });

  testWidgets('edição não permite reutilizar telefone de outro cliente', (
    tester,
  ) async {
    final auth = FakeAuth();
    auth._customers.add(
      const Customer(id: '2', name: 'Ana', phone: '851234567'),
    );
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.loadCustomers();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerFormPage(
          controller: controller,
          customer: auth._customers.first,
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Telefone (obrigatório)'),
      '+258 85 123 4567',
    );
    await tester.tap(find.text('Guardar alterações'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Este telefone já está registado para Ana'),
      findsOneWidget,
    );
    expect(auth._customers.first.phone, '84 123 4567');
  });

  testWidgets(
    'vendedor edita cliente, confirma duplicado e verifica resultado desconhecido',
    (tester) async {
      final auth = FakeAuth()..loseCustomerUpdateResponse = true;
      auth._customers.add(
        const Customer(id: '2', name: 'Ana', phone: '851234567'),
      );
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
      await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
      await tester.enterText(find.byType(TextFormField).at(1), 'correta');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Clientes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opções do cliente Maria Chongo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar cliente'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('vendas e pedidos anteriores'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do cliente'),
        'Ana',
      );
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Guardar alterações'));
      await tester.tap(find.text('Guardar alterações'));
      await tester.pumpAndSettle();
      expect(find.text('Possível duplicado'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(auth._customers.first.name, 'Maria Chongo');
      await tester.tap(find.text('Guardar alterações'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resultado desconhecido'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar alterações'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Voltar à lista'));
      await tester.tap(find.text('Voltar à lista'));
      await tester.pumpAndSettle();
      expect(auth._customers.first.name, 'Ana');
      expect(find.text('Ana'), findsNWidgets(2));
    },
  );

  testWidgets('pendências cruzam entrega e pagamento e atualizam após ações', (
    tester,
  ) async {
    final auth = FakeAuth()..loseSaleActionResponse = true;
    auth._sales.addAll(const [
      SaleRecord(
        id: '1',
        customerName: 'Ambas',
        seller: 'ana',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 10,
        items: [],
      ),
      SaleRecord(
        id: '2',
        customerName: 'Só pagamento',
        seller: 'ana',
        delivery: 'DELIVERED',
        payment: 'PENDING',
        total: 20,
        items: [],
      ),
      SaleRecord(
        id: '3',
        customerName: 'Só entrega',
        seller: 'ana',
        delivery: 'PENDING',
        payment: 'PAID',
        paymentMethod: 'BANK',
        total: 30,
        items: [],
      ),
      SaleRecord(
        id: '4',
        customerName: 'Cancelado',
        seller: 'ana',
        delivery: 'CANCELLED',
        payment: 'PENDING',
        total: 40,
        items: [],
      ),
      SaleRecord(
        id: '5',
        customerName: 'Pagamento antigo',
        seller: 'ana',
        delivery: 'DELIVERED',
        payment: 'PAID',
        total: 50,
        items: [],
      ),
    ]);
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesPage(
            controller: controller,
            isAdmin: false,
            onExpired: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ambas'), findsOneWidget);
    expect(find.text('Só entrega'), findsOneWidget);
    expect(find.text('Só pagamento'), findsNothing);
    expect(find.text('Cancelado'), findsNothing);
    await tester.tap(find.text('Por pagar'));
    await tester.pumpAndSettle();
    expect(find.text('Ambas'), findsOneWidget);
    expect(find.text('Só pagamento'), findsOneWidget);
    expect(find.text('Só entrega'), findsNothing);
    expect(find.text('Cancelado'), findsNothing);
    await tester.tap(find.text('Ambas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar pago'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('não comprova o recebimento externo'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Meio de pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M-Pesa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(auth.lastPaymentMethod, PaymentMethod.mpesa);
    expect(find.text('Ambas'), findsNothing);
    expect(find.text('Só pagamento'), findsOneWidget);
    expect(find.textContaining('Verifique o estado'), findsOneWidget);
    await tester.tap(find.text('Por entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ambas'));
    await tester.pumpAndSettle();
    expect(find.text('Meio de pagamento: M-Pesa'), findsOneWidget);
    expect(
      find.textContaining('Pedido pago não pode ser cancelado'),
      findsOneWidget,
    );
    expect(find.textContaining('reembolso indisponível'), findsOneWidget);
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Ambas'), findsNothing);
    await tester.ensureVisible(find.text('Entregues'));
    await tester.tap(find.text('Entregues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagamento antigo'));
    await tester.pumpAndSettle();
    expect(find.text('Meio de pagamento: Não informado'), findsOneWidget);
  });

  testWidgets('seleção de pagamento cabe em ecrã estreito com letra ampliada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth();
    auth._sales.add(
      const SaleRecord(
        id: '1',
        customerName: 'Cliente',
        seller: 'ana',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 10,
        items: [],
      ),
    );
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesPage(
            controller: controller,
            isAdmin: false,
            onExpired: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Marcar pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar pago'));
    await tester.pumpAndSettle();
    expect(find.text('Meio de pagamento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('venda paga exige meio e envia seleção', (tester) async {
    final auth = FakeAuth()..loseSaleCreateResponse = true;
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshAll();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleFormPage(controller: controller, onExpired: () {}),
      ),
    );
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do cliente'),
      'Cliente novo',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (obrigatório)'),
      '82 222 3333',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.'), '1');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.text('Pagamento recebido'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Pagamento recebido'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    expect(find.text('Selecione o meio de pagamento.'), findsOneWidget);
    expect(auth.lastSaleRequest, isNull);
    await tester.scrollUntilVisible(
      find.text('Meio de pagamento'),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Meio de pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banco').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    expect(auth.lastSaleRequest!['paymentMethod'], 'BANK');
    expect(auth._sales.single.paymentMethod, 'BANK');
    final operationId = auth.lastSaleRequest!['id'];
    expect(
      find.textContaining('resultado anterior pode ser desconhecido'),
      findsOneWidget,
    );
    auth.rejectSaleCreateBeforeSend = true;
    await tester.ensureVisible(find.text('Repetir envio'));
    await tester.tap(find.text('Repetir envio'));
    await tester.pumpAndSettle();
    expect(find.text('Repetir envio'), findsOneWidget);
    expect(
      find.textContaining('resultado anterior pode ser desconhecido'),
      findsOneWidget,
    );
    expect(auth.lastSaleRequest!['id'], operationId);
    auth.rejectSaleCreateBeforeSend = false;
    await tester.tap(find.text('Repetir envio'));
    await tester.pumpAndSettle();
    expect(auth.lastSaleRequest!['id'], operationId);
    expect(auth._sales.length, 1);
  });

  test('normaliza números de telefone de Moçambique', () {
    expect(normalizePhone('+258 84 123 4567'), '841234567');
    expect(normalizePhone('84 123 4567'), '841234567');
    expect(normalizePhone('00258841234567'), '841234567');
    expect(normalizePhone('   '), isNull);
  });

  test(
    'chave de cliente valida formatos e preserva códigos internacionais',
    () {
      for (final value in [
        '84 123 4567',
        '+258 84 123 4567',
        '00258-84-123-4567',
        '258841234567',
      ]) {
        expect(customerPhoneKey(value), '+258841234567');
      }
      expect(customerPhoneKey('+351 912 345 678'), '+351912345678');
      for (final value in [
        '',
        '123',
        '+258',
        'abc841234567',
        '84/123/4567',
        '+258+841234567',
      ]) {
        expect(customerPhoneKey(value), isNull);
      }
      expect(customerPhoneKey(null), isNull);
    },
  );

  test('formata preços sem perda de precisão decimal', () {
    expect(formatMoney('99999999999999999.99'), '99999999999999999.99 MT');
    expect(formatMoney('100.0'), '100.00 MT');
  });

  testWidgets('vendedor cria e edita produto dentro de Stock', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo produto'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do produto'),
      'Ovos grandes',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unidade'),
      'bandeja',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Preço em MT'),
      '125,50',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(auth._products.last.price, '125.50');
    expect(find.text('Ovos grandes'), findsOneWidget);
    await tester.tap(find.byTooltip('Opções do produto Ovos grandes'));
    await tester.pumpAndSettle();
    expect(find.text('Desativar produto'), findsNothing);
    await tester.tap(find.text('Editar produto'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Unidade'))
          .enabled,
      false,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Preço em MT'),
      '130',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(auth._products.last.price, '130');
  });

  testWidgets('resultado desconhecido de produto não permite duplicar envio', (
    tester,
  ) async {
    final auth = FakeAuth()..loseProductResponse = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo produto'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do produto'),
      'Produto teste',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Unidade'),
      'unidade',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Preço em MT'),
      '1',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('O resultado é desconhecido'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Voltar à lista'));
    await tester.tap(find.text('Voltar à lista'));
    await tester.pumpAndSettle();
    expect(find.text('Produto teste'), findsOneWidget);
    expect(auth._products.where((p) => p.name == 'Produto teste').length, 1);
  });

  testWidgets('administrador gere produtos e pode desativar', (tester) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Visão geral'), findsOneWidget);
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Novo produto'), findsOneWidget);
    expect(find.text('Atualizar stock'), findsNothing);
    await tester.tap(find.byTooltip('Opções do produto Ovos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desativar produto'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
    await tester.pumpAndSettle();
    expect(auth._products.first.active, false);
    expect(find.textContaining('Inativo'), findsOneWidget);
  });

  testWidgets('painel e stock administrativos cabem em ecrã estreito', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_tab('Relatórios'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('apagar vendedor pede confirmação e mantém operações', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    await auth.createSeller('ana', 'senha', 'Ana', null);
    auth._sales.add(
      const SaleRecord(
        id: 's1',
        customerName: 'Cliente',
        seller: 'ana',
        delivery: 'DELIVERED',
        payment: 'PAID',
        total: 10,
        items: [],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções do vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar vendedor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('não poderá ser reutilizado'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(auth._sellers.length, 1);
    await tester.tap(find.byTooltip('Opções do vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar vendedor'));
    await tester.pumpAndSettle();
    expect(auth._sellers, isEmpty);
    expect(auth._sales.single.seller, 'ana');
  });

  test('relatório escrito gera PDF vazio e com várias páginas', () async {
    final auth = FakeAuth();
    final empty = await auth.salesReport();
    final bytes = await buildSalesReportPdf(
      empty,
      DateTime(2026, 11, 11),
      PdfPageFormat.a4,
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(latin1.decode(bytes).contains('/Subtype/Image'), isTrue);
    final many = SalesReport(
      pendingOrders: 0,
      deliveredSales: 150,
      cancelledOperations: 0,
      pendingPayments: 1,
      markedPaid: 149,
      deliveredAmount: '99999999999999999.99',
      markedPaidAmount: '1.00',
      pendingPaymentAmount: '2.00',
      sellers: List.generate(
        150,
        (i) => SellerPerformance(
          seller: 'vendedor_$i',
          deliveredCount: 1,
          deliveredAmount: '1.00',
        ),
      ),
    );
    final longPdf = await buildSalesReportPdf(
      many,
      DateTime(2026, 11, 11),
      PdfPageFormat.a4,
    );
    expect(String.fromCharCodes(longPdf.take(4)), '%PDF');
    expect(longPdf.length, greaterThan(bytes.length));
  });

  testWidgets('impressão consulta dados atuais e apresenta falha', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    SalesReport? printed;
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminReportsPage(
            auth: auth,
            onExpired: () {},
            printer: (report, _) async {
              if (fail) throw StateError('impressora');
              printed = report;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    auth._sales.add(
      const SaleRecord(
        id: 's',
        customerName: 'C',
        seller: 'ana',
        delivery: 'DELIVERED',
        payment: 'PENDING',
        total: 50,
        items: [],
      ),
    );
    await tester.tap(find.text('Imprimir relatório escrito'));
    await tester.pumpAndSettle();
    expect(printed!.deliveredAmount, '50.00');
    fail = true;
    await tester.tap(find.text('Imprimir relatório escrito'));
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível preparar o relatório para impressão.'),
      findsOneWidget,
    );
  });

  testWidgets('administrador consulta clientes sem opção de registo', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Registar cliente'), findsNothing);
    await tester.tap(_tab('Clientes'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Chongo'), findsOneWidget);
    expect(find.text('Novo cliente'), findsNothing);
    expect(
      find.text('Lista de clientes. O estado ativo ainda não está definido.'),
      findsOneWidget,
    );
    expect(_tab('Produtos'), findsNothing);
  });

  testWidgets('administrador pode resolver entrega e pagamento sem cancelar', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    auth._sales.add(
      const SaleRecord(
        id: '1',
        customerName: 'Cliente pendente',
        seller: 'ana',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 50,
        items: [],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagamento pendente'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente pendente'), findsOneWidget);
    await tester.tap(find.text('Cliente pendente'));
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsNothing);
    expect(find.text('Marcar pago'), findsOneWidget);
    expect(find.text('Entregar'), findsOneWidget);
    expect(find.text('Cancelar pedido'), findsNothing);
    await tester.tap(find.text('Marcar pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meio de pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banco').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(auth._sales.single.seller, 'ana');
    expect(auth._sales.single.paymentMethod, 'BANK');
    expect(find.text('Cliente pendente'), findsNothing);
    await tester.tap(find.text('Por entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente pendente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(auth._sales.single.seller, 'ana');
    expect(auth._sales.single.delivery, 'DELIVERED');
    expect(find.text('Cliente pendente'), findsNothing);
  });

  testWidgets('vendedor vê apenas as próprias operações', (tester) async {
    final auth = FakeAuth();
    auth._sales.addAll(const [
      SaleRecord(
        id: 'own',
        customerName: 'Cliente próprio',
        seller: 'ana',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 10,
        items: [],
      ),
      SaleRecord(
        id: 'other',
        customerName: 'Cliente de outra venda',
        seller: 'bia',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 20,
        items: [],
      ),
    ]);
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesPage(
            controller: controller,
            isAdmin: false,
            onExpired: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cliente próprio'), findsOneWidget);
    expect(find.text('Cliente de outra venda'), findsNothing);
    await expectLater(
      auth.changeSale('other', 'deliver'),
      throwsA(isA<AuthException>()),
    );
    expect(auth._sales.last.delivery, 'PENDING');
    expect(auth.lastSaleAction, isNull);
  });

  testWidgets('administrador redefine e vendedor troca antes de entrar', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    auth._sellers.add(
      const SellerAccount(id: 's1', username: 'ana', enabled: true),
    );
    auth._passwords['ana'] = 'palavra-antiga';
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções do vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redefinir palavra-passe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirme a identidade'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Redefinir'));
    await tester.pumpAndSettle();
    const temporary = '0123456789abcdefghijklmnopqrstuv';
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      temporary,
    );
    expect(auth._passwords['ana'], temporary);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    auth.admin = false;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: LoginPage(auth: auth),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'ana');
    await tester.enterText(find.byType(TextFormField).at(1), temporary);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Antes de continuar, substitua a palavra-passe temporária.'),
      findsOneWidget,
    );
    expect(find.text('Nova venda'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Palavra-passe temporária'),
      temporary,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nova palavra-passe'),
      'nova-senha-forte',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar nova palavra-passe'),
      'nova-senha-forte',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Alterar palavra-passe'),
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Alterar palavra-passe'),
    );
    await tester.pumpAndSettle();
    expect(auth._passwords['ana'], 'nova-senha-forte');
    expect(
      find.text('Palavra-passe alterada. Inicie sessão novamente.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'nova-senha-forte',
    );
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsWidgets);
  });

  test(
    'nova conta de vendedor exige alterar a palavra-passe inicial',
    () async {
      final auth = FakeAuth()..admin = true;
      await auth.createSeller(
        'novo',
        'senha-inicial-123',
        'Novo Vendedor',
        null,
      );
      auth.admin = false;
      final session = await auth.login('novo', 'senha-inicial-123');
      expect(session.mustChangePassword, isTrue);
      await auth.changePassword('senha-inicial-123', 'senha-pessoal-123');
      final nextSession = await auth.login('novo', 'senha-pessoal-123');
      expect(nextSession.mustChangePassword, isFalse);
    },
  );

  testWidgets('administrador cria, edita e desativa vendedor', (tester) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Visão geral'), findsOneWidget);
    await tester.tap(_tab('Vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo vendedor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Ana Vendedora',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Utilizador'),
      'ana',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Palavra-passe inicial'),
      'senha1234567',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Vendedora'), findsOneWidget);
    await tester.tap(find.byTooltip('Opções do vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar dados'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Ana Atualizada',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Atualizada'), findsOneWidget);
    await tester.tap(find.byTooltip('Opções do vendedor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desativar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ana · Inativo'), findsOneWidget);
  });

  testWidgets(
    'relatório apresenta contagens reais e não inclui cancelados no pendente',
    (tester) async {
      final auth = FakeAuth()..admin = true;
      auth._sales.addAll([
        const SaleRecord(
          id: '1',
          customerName: 'A',
          seller: 'ana',
          delivery: 'DELIVERED',
          payment: 'PENDING',
          total: 50,
          items: [],
        ),
        const SaleRecord(
          id: '2',
          customerName: 'B',
          seller: 'ana',
          delivery: 'CANCELLED',
          payment: 'PENDING',
          total: 50,
          items: [],
        ),
      ]);
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
      await tester.enterText(find.byType(TextFormField).at(0), 'admin');
      await tester.enterText(find.byType(TextFormField).at(1), 'correta');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Relatórios'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Vendas entregues'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AdminReportsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Vendas entregues'), findsOneWidget);
      expect(find.text('Pagamentos pendentes'), findsOneWidget);
      final table = tester.widget<Table>(find.byType(Table).first);
      final pending = table.children[3].children;
      expect(
        (pending[1] as Padding).child,
        isA<Text>().having((t) => t.data, 'contagem', '1'),
      );
      expect(
        (pending[2] as Padding).child,
        isA<Text>().having((t) => t.data, 'valor', '50.00 MT'),
      );
      await tester.scrollUntilVisible(
        find.text('ana'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(AdminReportsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final seller = find.ancestor(
        of: find.text('ana'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: seller, matching: find.text('50.00 MT')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'relatório recupera de falha e carrega detalhes apenas quando pedido',
    (tester) async {
      final auth = FakeAuth()
        ..admin = true
        ..failReports = true;
      auth._sales.add(
        const SaleRecord(
          id: '1',
          customerName: 'Cliente detalhe',
          seller: 'ana',
          delivery: 'DELIVERED',
          payment: 'PAID',
          total: 50,
          items: [],
        ),
      );
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
      await tester.enterText(find.byType(TextFormField).at(0), 'admin');
      await tester.enterText(find.byType(TextFormField).at(1), 'correta');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Relatórios'));
      await tester.pumpAndSettle();
      expect(find.text('Relatório indisponível'), findsOneWidget);
      expect(auth.salesCalls, 0);
      auth.failReports = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Vendas entregues'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(AdminReportsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Vendas entregues'), findsOneWidget);
      expect(auth.salesCalls, 0);
      await tester.scrollUntilVisible(
        find.text('Operações registadas'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(AdminReportsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operações registadas'));
      await tester.pumpAndSettle();
      expect(auth.salesCalls, 1);
      await tester.scrollUntilVisible(
        find.text('Cliente detalhe'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(AdminReportsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Cliente detalhe'), findsOneWidget);
    },
  );

  testWidgets('erro de produtos permite repetir sem mostrar dados antigos', (
    tester,
  ) async {
    final auth = FakeAuth()..failProducts = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Falha ao carregar produtos'), findsOneWidget);
    expect(find.text('Ovos'), findsNothing);
    auth.failProducts = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ovos'), findsOneWidget);
  });

  testWidgets('sessão recusada regressa ao login', (tester) async {
    final auth = FakeAuth()..expired = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'vendedor');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(
      find.text('A sessão terminou. Inicie sessão novamente.'),
      findsOneWidget,
    );
    expect(find.text('Iniciar sessão'), findsOneWidget);
  });

  testWidgets('consulta pagina e filtra apenas operações autorizadas', (
    tester,
  ) async {
    final auth = FakeAuth();
    for (var i = 0; i < 23; i++) {
      auth._sales.add(
        SaleRecord(
          id: 'sale-$i',
          customerName: 'Cliente $i',
          seller: 'ana',
          delivery: 'PENDING',
          payment: 'PENDING',
          total: 10,
          items: const ['Ovos'],
        ),
      );
    }
    auth._sales.add(
      const SaleRecord(
        id: 'outra',
        customerName: 'Cliente secreto',
        seller: 'bia',
        delivery: 'PENDING',
        payment: 'PENDING',
        total: 10,
        items: ['Ovos'],
      ),
    );
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesPage(
            controller: controller,
            isAdmin: false,
            onExpired: () {},
            onNewSale: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Página 1'), findsOneWidget);
    await tester.tap(find.text('Seguinte'));
    await tester.pumpAndSettle();
    expect(find.text('Página 2'), findsOneWidget);
    expect(find.text('Cliente secreto'), findsNothing);
    await tester.tap(find.text('Pesquisar e filtrar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cliente'),
      'Cliente 22',
    );
    await tester.tap(find.text('Pesquisar'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Cliente 22'),
      findsOneWidget,
    );
    expect(find.text('Cliente secreto'), findsNothing);
  });

  testWidgets('venda preserva itens escolhidos ao pesquisar outros produtos', (
    tester,
  ) async {
    final auth = FakeAuth();
    auth._products.add(
      const Product(id: 'p2', name: 'Caixas', unit: 'caixa', price: '20'),
    );
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshAll();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleFormPage(controller: controller, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Qtd.').first, '2');
    await tester.enterText(
      find.widgetWithText(TextField, 'Pesquisar produto'),
      'Caixas',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Novo cliente'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do cliente'),
      'Cliente fictício',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (obrigatório)'),
      '857654321',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirmar venda'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(SaleFormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Ovos'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    final items = auth.lastSaleRequest!['items'] as List;
    expect(items, hasLength(1));
    expect(items.single['productId'], 'p1');
    expect(items.single['quantity'], '2');
  });

  testWidgets('stock mínimo configurado destaca saldo disponível baixo', (
    tester,
  ) async {
    final auth = FakeAuth()..stockQuantity = 2;
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshStock();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockPage(controller: controller, onExpired: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções do produto Ovos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock mínimo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Mínimo em bandeja'),
      '3,00',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(auth._products.single.minimumStock, '3.00');
    expect(find.text('Stock baixo'), findsOneWidget);
    expect(controller.balances['p1']!.available, 2);
    await tester.tap(find.byTooltip('Opções do produto Ovos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock mínimo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover mínimo'));
    await tester.pumpAndSettle();
    expect(auth._products.single.minimumStock, isNull);
    expect(find.text('Stock baixo'), findsNothing);
    expect(controller.balances['p1']!.available, 2);
  });

  testWidgets('alerta de stock cabe em ecrã estreito com texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth()..stockQuantity = 2;
    auth._products[0] = const Product(
      id: 'p1',
      name: 'Ovos',
      unit: 'bandeja',
      price: '100',
      minimumStock: '3.00',
    );
    final controller = SellerController(auth);
    addTearDown(controller.dispose);
    await controller.refreshStock();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockPage(controller: controller, onExpired: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stock baixo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relatório escolhe datas de Maputo e abre auditoria administrativa',
    (tester) async {
      final auth = FakeAuth()..admin = true;
      auth.auditRows.add(
        AuditRecord(
          actor: 'ana',
          action: 'SALE_DELIVERED',
          targetType: 'SALE',
          targetId: 'ficticio',
          detail: 'delivery=DELIVERED',
          occurredAt: DateTime.utc(2026, 11, 23),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminReportsPage(auth: auth, onExpired: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();
      expect(auth.reportFrom, isNotNull);
      expect(auth.reportFrom, auth.reportTo);
      expect(find.textContaining('horário de Maputo'), findsWidgets);
      await tester.tap(find.text('Histórico administrativo'));
      await tester.pumpAndSettle();
      expect(find.text('Entrega registada'), findsOneWidget);
      expect(
        find.textContaining('não é completo nem inviolável'),
        findsOneWidget,
      );
    },
  );

  testWidgets('falha no período permite voltar ao histórico completo', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..admin = true
      ..failPeriodReports = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminReportsPage(auth: auth, onExpired: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoje'));
    await tester.pumpAndSettle();
    expect(find.text('Servidor não suporta o período.'), findsOneWidget);
    await tester.tap(find.text('Voltar ao histórico completo'));
    await tester.pumpAndSettle();
    expect(find.text('Todos os eventos registados.'), findsOneWidget);
  });

  testWidgets(
    'administrador entra sem código e é avisado se a saída não for confirmada',
    (tester) async {
      final auth = FakeAuth()..admin = true;
      await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Utilizador'),
        'admin',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Palavra-passe'),
        'correta',
      );
      expect(find.text('Administrador: introduzir código'), findsNothing);
      expect(find.text('Código do autenticador (administrador)'), findsNothing);
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminShell), findsOneWidget);
      auth.logoutFails = true;
      await tester.tap(find.byTooltip('Terminar sessão'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'não foi possível confirmar o encerramento no servidor',
        ),
        findsOneWidget,
      );
    },
  );

  test('não envia credenciais por HTTP', () async {
    await expectLater(
      HttpAuthService('http://localhost:8080').login('u', 'p'),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'não permite certificado de desenvolvimento para outro servidor',
    () async {
      await expectLater(
        HttpAuthService(
          'https://example.com',
          developmentCertificate: 'AA==',
        ).login('u', 'p'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('não permitido'),
          ),
        ),
      );
    },
  );
}
