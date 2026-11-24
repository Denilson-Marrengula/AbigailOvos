import 'dart:convert';

import 'package:abigailovos/admin/activity_report_page.dart';
import 'package:abigailovos/admin/activity_report_pdf.dart';
import 'package:abigailovos/admin/admin_shell.dart';
import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'widget_test.dart' show FakeAuth;

Map<String, dynamic> reportJson() {
  final operation = <String, dynamic>{
    'id': 'venda-ficticia',
    'customerName': 'Cliente Fictício',
    'customerPhone': null,
    'seller': 'ana',
    'amount': '100.10',
    'createdAt': '2026-02-20T08:00:00Z',
    'deliveredAt': '2026-02-24T08:00:00Z',
    'paidAt': null,
    'deliveryStatus': 'DELIVERED',
    'paymentStatus': 'PENDING',
    'paymentMethod': null,
    'items': [
      {
        'name': 'Ovos',
        'unit': 'bandeja',
        'quantity': '2.00',
        'unitPrice': '50.05',
        'lineTotal': '100.10',
      },
    ],
  };
  final payment = <String, dynamic>{
    ...operation,
    'id': 'paga-ficticia',
    'paymentStatus': 'PAID',
    'paymentMethod': 'MPESA',
    'paidAt': '2026-02-26T09:00:00Z',
  };
  final order = <String, dynamic>{
    ...operation,
    'id': 'pedido-ficticio',
    'customerName': 'Cliente com pedido',
    'deliveryStatus': 'PENDING',
    'deliveredAt': null,
  };
  return {
    'periodStart': '2026-02-23',
    'periodEnd': '2026-03-01',
    'timeZone': 'Africa/Maputo',
    'queriedAt': '2026-03-02T12:30:00Z',
    'unknownDeliveredDates': 2,
    'unknownPaidDates': 1,
    'deliveredAmount': '100.10',
    'debtAmount': '100.10',
    'pendingOrderAmount': '100.10',
    'paidAmount': '100.10',
    'deliveredCustomers': [
      {
        'customerId': 'cliente-1',
        'name': 'Cliente Fictício',
        'phone': null,
        'operations': 1,
        'amount': '100.10',
      },
    ],
    'debtCustomers': [
      {
        'customerId': 'cliente-1',
        'name': 'Cliente Fictício',
        'phone': null,
        'operations': 1,
        'amount': '100.10',
      },
    ],
    'pendingOrders': [order],
    'paymentMethods': [
      {'method': 'EMOLA', 'operations': 0, 'amount': '0.00'},
      {'method': 'MPESA', 'operations': 1, 'amount': '100.10'},
      {'method': 'BANK', 'operations': 0, 'amount': '0.00'},
      {'method': 'CASH', 'operations': 0, 'amount': '0.00'},
      {'method': 'UNKNOWN', 'operations': 0, 'amount': '0.00'},
    ],
    'payments': [payment],
    'sellers': [
      {'seller': 'ana', 'operations': 1, 'amount': '100.10'},
    ],
    'deliveries': [operation],
  };
}

ActivityReport sample() =>
    ActivityReport.fromJson(reportJson(), from: '2026-02-23', to: '2026-03-01');

void main() {
  test('relatório exige período e fuso corretos e preserva dinheiro exato', () {
    final json = reportJson();
    json['deliveredAmount'] = '90071992547409.99';
    final report = ActivityReport.fromJson(
      json,
      from: '2026-02-23',
      to: '2026-03-01',
    );
    expect(report.deliveredAmount, '90071992547409.99');
    expect(report.deliveries.single.seller, 'ana');
    expect(report.deliveries.single.items.single.unitPrice, '50.05');
    expect(
      () => ActivityReport.fromJson(json, from: '2026-02-24', to: '2026-03-01'),
      throwsFormatException,
    );
    final wrongZone = Map<String, dynamic>.from(json)..['timeZone'] = 'UTC';
    expect(
      () => ActivityReport.fromJson(
        wrongZone,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final numericMoney = Map<String, dynamic>.from(json)..['debtAmount'] = 1.1;
    expect(
      () => ActivityReport.fromJson(
        numericMoney,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final badStatus = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    badStatus['deliveries'][0]['paymentStatus'] = 'UNKNOWN';
    expect(
      () => ActivityReport.fromJson(
        badStatus,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final missingMethod = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (missingMethod['paymentMethods'] as List).removeLast();
    expect(
      () => ActivityReport.fromJson(
        missingMethod,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final wrongTotal = Map<String, dynamic>.from(json)
      ..['paidAmount'] = '100.11';
    expect(
      () => ActivityReport.fromJson(
        wrongTotal,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final wrongMethod = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    wrongMethod['paymentMethods'][0]['operations'] = 1;
    wrongMethod['paymentMethods'][0]['amount'] = '100.10';
    wrongMethod['paymentMethods'][1]['operations'] = 0;
    wrongMethod['paymentMethods'][1]['amount'] = '0.00';
    expect(
      () => ActivityReport.fromJson(
        wrongMethod,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
    final wrongEvent = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    wrongEvent['deliveries'][0]['deliveredAt'] = '2026-02-20T08:00:00Z';
    expect(
      () => ActivityReport.fromJson(
        wrongEvent,
        from: '2026-02-23',
        to: '2026-03-01',
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'semana de Maputo, mês anterior, detalhes e impressão usam o período escolhido',
    (tester) async {
      final auth = FakeAuth()
        ..admin = true
        ..activityData = sample();
      ActivityReport? printed;
      bool? printedMonthly;
      await tester.pumpWidget(
        MaterialApp(
          home: ActivityReportPage(
            auth: auth,
            onExpired: () {},
            now: () => DateTime.utc(2026, 3, 1, 23, 30),
            printer: (report, monthly) async {
              printed = report;
              printedMonthly = monthly;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.activityFrom, DateTime.utc(2026, 2, 23));
      expect(auth.activityTo, DateTime.utc(2026, 3, 1));
      expect(find.text('23/02/2026 a 01/03/2026'), findsOneWidget);
      expect(
        find.textContaining('Dívidas, pedidos e estados: atuais'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mensal'));
      await tester.pumpAndSettle();
      expect(auth.activityFrom, DateTime.utc(2026, 2, 1));
      expect(auth.activityTo, DateTime.utc(2026, 2, 28));
      expect(find.text('01/02/2026 a 28/02/2026'), findsOneWidget);

      final scroll = find
          .descendant(
            of: find.byType(ActivityReportPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Vendas entregues: detalhes'),
        180,
        scrollable: scroll,
      );
      await tester.tap(find.text('Vendas entregues: detalhes'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Cliente Fictício'),
        150,
        scrollable: scroll,
      );
      await tester.tap(find.text('Cliente Fictício'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Vendedor que registou: ana'),
        120,
        scrollable: scroll,
      );
      expect(find.text('Vendedor que registou: ana'), findsOneWidget);
      expect(find.text('Ovos'), findsOneWidget);
      final updated = reportJson()..['queriedAt'] = '2026-03-02T13:00:00Z';
      auth.activityData = ActivityReport.fromJson(
        updated,
        from: '2026-02-23',
        to: '2026-03-01',
      );
      await tester.scrollUntilVisible(
        find.text('Imprimir ou guardar PDF'),
        -250,
        scrollable: scroll,
      );
      final scrollState = tester.state<ScrollableState>(scroll);
      scrollState.position.jumpTo(scrollState.position.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Imprimir ou guardar PDF'));
      await tester.pumpAndSettle();
      expect(printedMonthly, true);
      expect(printed!.periodStart, '2026-02-01');
      expect(printed!.periodEnd, '2026-02-28');
      expect(printed!.queriedAt, DateTime.utc(2026, 3, 2, 13));
    },
  );

  testWidgets('relatórios detalhados cabem em ecrã estreito e geram PDF', (
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
    final auth = FakeAuth()
      ..admin = true
      ..activityData = sample();
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(auth: auth, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final bytes = await buildActivityReportPdf(
      sample(),
      true,
      PdfPageFormat.a4,
    );
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('explicações ficam acessíveis e avisos essenciais visíveis', (
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
    final auth = FakeAuth()
      ..admin = true
      ..activityData = sample();
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(auth: auth, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('período selecionado'), findsOneWidget);
    expect(find.textContaining('atuais, de todo o histórico'), findsOneWidget);
    expect(
      find.text('Pagamentos marcados não comprovam recebimento externo.'),
      findsOneWidget,
    );
    final scroll = find
        .descendant(
          of: find.byType(ActivityReportPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.textContaining('2 entregas e 1 pagamento'),
      120,
      scrollable: scroll,
    );
    expect(find.textContaining('2 entregas e 1 pagamento'), findsOneWidget);
    expect(
      find.textContaining('Não entram nos totais do período.'),
      findsOneWidget,
    );
    expect(
      find.text('Dívida: entregas não pagas de valor positivo.'),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.text('Como ler o relatório'),
      180,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Como ler o relatório'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Como ler o relatório'));
    await tester.pumpAndSettle();
    expect(
      find.text('Clientes do período são os que receberam entregas.'),
      findsOneWidget,
    );
    expect(
      find.text('Dívida: entregas não pagas de valor positivo.'),
      findsOneWidget,
    );
    expect(
      find.text('Pedidos por entregar podem já estar pagos.'),
      findsOneWidget,
    );
    expect(
      find.text('O resumo geral inclui pedidos não pagos nas pendências.'),
      findsOneWidget,
    );
    expect(
      find.text('Por isso, podem ser maiores do que a dívida aqui.'),
      findsOneWidget,
    );
    expect(
      find.text('Pendências e estados não são um fecho histórico.'),
      findsOneWidget,
    );
    expect(
      find.text('Os nomes e contactos dos clientes são os atuais.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem datas desconhecidas não mostra aviso de histórico', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(auth: auth, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem data no histórico:'), findsNothing);
    expect(
      find.text('A impressão consulta dados atualizados.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'resumo geral distingue datas desconhecidas e pendências atuais',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final auth = FakeAuth()
        ..admin = true
        ..reportUnknownDeliveredDates = 2
        ..reportUnknownPaidDates = 1
        ..reportUnknownCancelledDates = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminReportsPage(auth: auth, onExpired: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Pendências: atuais, de todo o histórico.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 entregas, 1 pagamento e 3 cancelamentos'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Incluídos no histórico total.'),
        findsOneWidget,
      );
      final scroll = find
          .descendant(
            of: find.byType(AdminReportsPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Pagamentos marcados não comprovam recebimento externo.'),
        160,
        scrollable: scroll,
      );
      expect(
        find.text('Pagamentos marcados não comprovam recebimento externo.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Como ler o resumo'),
        180,
        scrollable: scroll,
      );
      await tester.ensureVisible(find.text('Como ler o resumo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Entregas e pagamentos são independentes.'),
        findsNothing,
      );
      await tester.tap(find.text('Como ler o resumo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Entregas e pagamentos são independentes.'),
        findsOneWidget,
      );
      expect(
        find.text('Pagamentos marcados podem incluir pedidos por entregar.'),
        findsOneWidget,
      );
      expect(
        find.text('Pagamentos pendentes incluem pedidos não pagos.'),
        findsOneWidget,
      );
      expect(
        find.text('Pendências são atuais e excluem cancelamentos.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'dívida inclui apenas entregas não pagas de valor positivo',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Hoje'),
        -180,
        scrollable: scroll,
      );
      await tester.ensureVisible(find.text('Hoje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();
      expect(auth.reportFrom, isNotNull);
      await tester.scrollUntilVisible(
        find.textContaining('Excluídos dos totais do período.'),
        120,
        scrollable: scroll,
      );
      expect(
        find.textContaining('Excluídos dos totais do período.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resumo geral mantém aviso de servidor sem datas de eventos', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..admin = true
      ..reportEventDatesSupported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminReportsPage(auth: auth, onExpired: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Este servidor não informa as datas dos eventos'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pendências: situação atual de todo o histórico'),
      findsOneWidget,
    );
  });

  testWidgets('PDF semanal e mensal suportam listas com várias páginas', (
    tester,
  ) async {
    final data = reportJson();
    data['deliveredCustomers'] = List.generate(
      150,
      (i) => {
        'customerId': 'cliente-$i',
        'name': 'Cliente fictício número $i',
        'phone': null,
        'operations': 1,
        'amount': '100.10',
      },
    );
    final many = ActivityReport.fromJson(
      data,
      from: '2026-02-23',
      to: '2026-03-01',
    );
    final weekly = await buildActivityReportPdf(many, false, PdfPageFormat.a4);
    final monthly = await buildActivityReportPdf(many, true, PdfPageFormat.a4);
    expect(String.fromCharCodes(weekly.take(4)), '%PDF');
    expect(String.fromCharCodes(monthly.take(4)), '%PDF');
    expect(weekly.length, greaterThan(1000));
    expect(monthly.length, greaterThan(1000));
    expect(latin1.decode(weekly).contains('/Subtype/Image'), isTrue);
    expect(
      RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(weekly)).length,
      greaterThan(1),
    );
  });

  testWidgets('mês anterior respeita ano bissexto e falha permite repetir', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..admin = true
      ..failActivityReports = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(
          auth: auth,
          onExpired: () {},
          now: () => DateTime.utc(2024, 3, 1, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Relatório indisponível.'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Relatório indisponível.'), findsOneWidget);
    auth.failActivityReports = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mensal'));
    await tester.pumpAndSettle();
    expect(auth.activityFrom, DateTime.utc(2024, 2, 1));
    expect(auth.activityTo, DateTime.utc(2024, 2, 29));
  });

  testWidgets('administrador abre relatórios semanais e mensais', (
    tester,
  ) async {
    final auth = FakeAuth()..admin = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminReportsPage(auth: auth, onExpired: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(AdminReportsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Relatórios semanais e mensais'),
      180,
      scrollable: scroll,
    );
    await tester.tap(find.text('Relatórios semanais e mensais'));
    await tester.pumpAndSettle();
    expect(find.text('Relatórios detalhados'), findsOneWidget);
    expect(find.text('Semanal'), findsOneWidget);
  });

  testWidgets('listas grandes são paginadas sem perder clientes', (
    tester,
  ) async {
    final data = reportJson();
    data['deliveredCustomers'] = List.generate(
      23,
      (i) => {
        'customerId': 'cliente-$i',
        'name': 'Cliente exemplo $i',
        'phone': null,
        'operations': 1,
        'amount': '1.00',
      },
    );
    final report = ActivityReport.fromJson(
      data,
      from: '2026-02-23',
      to: '2026-03-01',
    );
    final auth = FakeAuth()
      ..admin = true
      ..activityData = report;
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(auth: auth, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(ActivityReportPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Clientes com entregas no período'),
      160,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Clientes com entregas no período'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clientes com entregas no período'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Seguinte'));
    await tester.pumpAndSettle();
    expect(find.text('Página 1 de 2'), findsOneWidget);
    await tester.tap(find.text('Seguinte'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Clientes com entregas no período'),
      -200,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Clientes com entregas no período'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cliente exemplo 20'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente exemplo 20'), findsOneWidget);
    expect(find.text('Página 2 de 2'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Clientes com entregas no período'),
      -200,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Clientes com entregas no período'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente exemplo 20'), findsOneWidget);
    expect(find.text('Página 2 de 2'), findsOneWidget);
  });

  testWidgets('meios de pagamento identificam valores e clientes', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..admin = true
      ..activityData = sample();
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityReportPage(auth: auth, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(ActivityReportPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Meios de pagamento no período'),
      180,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Meios de pagamento no período'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meios de pagamento no período'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('M-Pesa'));
    await tester.pumpAndSettle();
    expect(find.text('1 pagamento · 100.10 MT'), findsOneWidget);
    await tester.ensureVisible(find.text('Pagamentos por cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagamentos por cliente'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cliente Fictício'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Marcado como pago (M-Pesa)'), findsOneWidget);
  });
}
