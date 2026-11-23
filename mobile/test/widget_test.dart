import 'package:abigailovos/auth/auth_service.dart';
import 'package:abigailovos/admin/admin_shell.dart';
import 'package:abigailovos/auth/login_page.dart';
import 'package:abigailovos/design/app_logo.dart';
import 'package:abigailovos/main.dart';
import 'package:abigailovos/seller/seller_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth implements AuthService {
  bool admin = false;
  bool failProducts = false;
  bool expired = false;
  bool failReports = false;
  int salesCalls = 0;
  Map<String, dynamic>? lastSaleRequest;
  Map<String, dynamic>? lastStockRequest;
  bool loseStockResponseOnce = false;
  final Set<String> _stockOperationIds = {};
  num stockQuantity = 12;
  final List<SellerAccount> _sellers = [];
  @override
  Future<List<SellerAccount>> sellers() async => List.of(_sellers);
  @override
  Future<void> createSeller(
    String username,
    String password,
    String name,
    String? phone,
  ) async {
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

  final List<SaleRecord> _sales = [];
  @override
  Future<List<SaleRecord>> sales() async {
    salesCalls++;
    return List.of(_sales);
  }
  @override
  Future<SalesReport> salesReport() async {
    if (failReports) throw const AuthException('Relatório indisponível');
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
    );
  }

  @override
  Future<void> createSale(Map<String, dynamic> request) async {
    lastSaleRequest = request;
    final newCustomer = request['customer'] as Map<String, dynamic>?;
    if (newCustomer != null) {
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
        seller: 'vendedor',
        delivery: request['deliverNow'] == true ? 'DELIVERED' : 'PENDING',
        payment: request['paid'] == true ? 'PAID' : 'PENDING',
        total: 100,
        items: const ['1 bandeja · Ovos'],
      ),
    );
  }

  @override
  Future<void> changeSale(String id, String action) async {}
  final List<Customer> _customers = [
    const Customer(id: '1', name: 'Maria Chongo', phone: '84 123 4567'),
  ];

  @override
  void logout() {}

  @override
  Future<AuthSession> login(String username, String password) async {
    if (password != 'correta') throw const AuthException('Dados inválidos');
    return AuthSession(
      username: username,
      roles: [admin ? 'ROLE_ADMIN' : 'ROLE_SELLER'],
    );
  }

  @override
  Future<List<Product>> products() async {
    if (expired) {
      throw const AuthException('Sessão terminada', sessionExpired: true);
    }
    if (failProducts) throw const AuthException('Falha ao carregar produtos');
    return [
      const Product(id: 'p1', name: 'Ovos', unit: 'bandeja', price: '100.0'),
    ];
  }

  @override
  Future<List<Customer>> customers() async => List.of(_customers);

  @override
  Future<Customer> createCustomer(String name, String? phone) async {
    final customer = Customer(
      id: '${_customers.length + 1}',
      name: name,
      phone: phone,
    );
    _customers.add(customer);
    return customer;
  }

  @override
  Future<StockBalance> stockBalance(String productId) async => StockBalance(
    physical: stockQuantity,
    reserved: 0,
    available: stockQuantity,
  );

  @override
  Future<void> createStockMovement(Map<String, dynamic> request) async {
    lastStockRequest = request;
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

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('identifica o ambiente isolado sem marcar a aplicação normal', (
    tester,
  ) async {
    await tester.pumpWidget(const AbigailOvosApp());
    await tester.pumpAndSettle();
    expect(
      find.text('AMBIENTE DE TESTE — NÃO USAR DADOS REAIS'),
      const bool.fromEnvironment('ISOLATED_TEST')
          ? findsOneWidget
          : findsNothing,
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
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Joana Mabunda');
    await tester.enterText(find.byType(TextField).at(1), '857654321');
    await tester.enterText(find.byType(TextField).at(2), '1');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar venda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concluídas'));
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
    expect(find.text('Confirmar venda'), findsOneWidget);
    expect(find.text('Novo cliente'), findsOneWidget);
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motivo'),
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
    expect(find.text('Stock atualizado.'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(auth.lastStockRequest!['type'], 'ENTRY');
    expect(auth.lastStockRequest!['quantity'], '3');
    expect(auth.lastStockRequest!['operationId'], isA<String>());
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
        find.widgetWithText(TextFormField, 'Motivo'),
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
    await tester.enterText(find.byType(TextField).at(0), 'Maria Chongo');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Possível cliente já registado: Maria Chongo'),
      findsOneWidget,
    );
  });

  test('normaliza números de telefone de Moçambique', () {
    expect(normalizePhone('+258 84 123 4567'), '841234567');
    expect(normalizePhone('84 123 4567'), '841234567');
    expect(normalizePhone('00258841234567'), '841234567');
    expect(normalizePhone('   '), isNull);
  });

  test('formata preços sem perda de precisão decimal', () {
    expect(formatMoney('99999999999999999.99'), '99999999999999999.99 MT');
    expect(formatMoney('100.0'), '100.00 MT');
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

  testWidgets('administrador cria, edita e desativa vendedor', (tester) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'correta');
    await tester.tap(find.text('Entrar'));
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
      expect(find.text('Vendas entregues'), findsOneWidget);
      expect(find.text('Pagamentos pendentes'), findsOneWidget);
      final pending = find.ancestor(
        of: find.text('Pagamentos pendentes'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: pending, matching: find.text('1')),
        findsOneWidget,
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

  testWidgets('relatório recupera de falha e carrega detalhes apenas quando pedido', (tester) async {
    final auth = FakeAuth()..admin = true..failReports = true;
    auth._sales.add(const SaleRecord(id: '1', customerName: 'Cliente detalhe', seller: 'ana', delivery: 'DELIVERED', payment: 'PAID', total: 50, items: []));
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
    expect(find.text('Vendas entregues'), findsOneWidget);
    expect(auth.salesCalls, 0);
    await tester.scrollUntilVisible(find.text('Operações registadas'), 250,
      scrollable: find.descendant(of: find.byType(AdminReportsPage), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Operações registadas'));
    await tester.pumpAndSettle();
    expect(auth.salesCalls, 1);
    await tester.scrollUntilVisible(find.text('Cliente detalhe'), 150,
      scrollable: find.descendant(of: find.byType(AdminReportsPage), matching: find.byType(Scrollable)).first);
    expect(find.text('Cliente detalhe'), findsOneWidget);
  });

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
