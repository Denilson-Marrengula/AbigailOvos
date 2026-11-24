import 'package:abigailovos/admin/admin_shell.dart';
import 'package:abigailovos/admin/report_charts.dart';
import 'package:abigailovos/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeAuth;

SalesReport _report({
  int deliveries = 8,
  int paid = 4,
  int cancelled = 2,
  int pendingOrders = 6,
  int pendingPayments = 3,
  String? from,
  String? to,
}) => SalesReport(
  pendingOrders: pendingOrders,
  deliveredSales: deliveries,
  cancelledOperations: cancelled,
  pendingPayments: pendingPayments,
  markedPaid: paid,
  deliveredAmount: '123.45',
  markedPaidAmount: '67.89',
  pendingPaymentAmount: '20.00',
  sellers: const [],
  periodStart: from,
  periodEnd: to,
);

class _ChartsAuth extends FakeAuth {
  bool fail = false;

  @override
  Future<SalesReport> salesReport({DateTime? from, DateTime? to}) async {
    if (fail) throw const AuthException('Relatório indisponível.');
    reportFrom = from;
    reportTo = to;
    if (from == null) return _report();
    String day(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return _report(
      deliveries: 2,
      paid: 3,
      cancelled: 1,
      from: day(from),
      to: day(to!),
    );
  }
}

double? _bar(WidgetTester tester, String name) => tester
    .widget<LinearProgressIndicator>(find.byKey(ValueKey('report-bar-$name')))
    .value;

void main() {
  testWidgets('gráficos usam quantidades reais e escalas independentes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesReportCharts(report: _report())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atividade no histórico'), findsOneWidget);
    expect(find.text('Pendências atuais'), findsOneWidget);
    expect(find.text('Quantidade de eventos'), findsOneWidget);
    expect(find.text('Todo o histórico'), findsOneWidget);
    expect(_bar(tester, 'delivered'), 1);
    expect(_bar(tester, 'paid'), .5);
    expect(_bar(tester, 'cancelled'), .25);
    expect(_bar(tester, 'pending-orders'), 1);
    expect(_bar(tester, 'pending-payments'), .5);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(
      find.textContaining('uma operação pode aparecer mais de uma vez'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('gráficos vazios e contagens inválidas não simulam dados', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesReportCharts(
              report: _report(
                deliveries: 0,
                paid: 0,
                cancelled: 0,
                pendingOrders: 0,
                pendingPayments: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_bar(tester, 'delivered'), 0);
      expect(_bar(tester, 'pending-payments'), 0);
      expect(find.text('0'), findsNWidgets(5));
      expect(find.bySemanticsLabel('Entregas: 0'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesReportCharts(report: _report(deliveries: -1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Dados do gráfico inválidos. Atualize o relatório.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('report-bar-delivered')), findsNothing);
    expect(_bar(tester, 'pending-orders'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relatório principal mostra gráficos e atualiza os eventos ao filtrar',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final auth = _ChartsAuth()..admin = true;
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
        find.text('Atividade no histórico'),
        160,
        scrollable: scroll,
      );
      expect(_bar(tester, 'delivered'), 1);
      expect(_bar(tester, 'paid'), .5);
      expect(
        find.text('Pagamentos marcados não comprovam recebimento externo.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Pendências atuais'),
        160,
        scrollable: scroll,
      );
      expect(_bar(tester, 'pending-orders'), 1);
      expect(_bar(tester, 'pending-payments'), .5);

      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();
      expect(auth.reportFrom, isNotNull);
      await tester.scrollUntilVisible(
        find.text('Atividade no período'),
        160,
        scrollable: scroll,
      );
      expect(_bar(tester, 'delivered'), closeTo(2 / 3, .0001));
      expect(_bar(tester, 'paid'), 1);
      expect(_bar(tester, 'cancelled'), closeTo(1 / 3, .0001));
      await tester.scrollUntilVisible(
        find.text('Pendências atuais'),
        160,
        scrollable: scroll,
      );
      expect(_bar(tester, 'pending-orders'), 1);
      expect(_bar(tester, 'pending-payments'), .5);

      auth.fail = true;
      final currentPosition = tester.state<ScrollableState>(scroll).position;
      currentPosition.jumpTo(currentPosition.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Últimos 7 dias'));
      await tester.pumpAndSettle();
      expect(find.text('Relatório indisponível.'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-events-chart')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
