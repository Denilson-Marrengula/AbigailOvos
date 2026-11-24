import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../seller/seller_widgets.dart';
import 'activity_report_pdf.dart';

/// Relatórios consultados a pedido. Nenhum fecho histórico é criado em segundo plano.
class ActivityReportPage extends StatefulWidget {
  const ActivityReportPage({
    super.key,
    required this.auth,
    required this.onExpired,
    this.now,
    this.printer,
  });
  final AuthService auth;
  final VoidCallback onExpired;
  final DateTime Function()? now;
  final Future<bool> Function(ActivityReport, bool)? printer;

  @override
  State<ActivityReportPage> createState() => _ActivityReportPageState();
}

class _ActivityReportPageState extends State<ActivityReportPage> {
  late DateTime start;
  late Future<ActivityReport> report;
  bool monthly = false;
  bool printing = false;

  @override
  void initState() {
    super.initState();
    start = _currentStart(false).subtract(const Duration(days: 7));
    report = _load(start, monthly);
  }

  DateTime _currentStart(bool month) {
    final local = (widget.now?.call() ?? DateTime.now()).toUtc().add(
      const Duration(hours: 2),
    );
    final today = DateTime.utc(local.year, local.month, local.day);
    return month
        ? DateTime.utc(today.year, today.month)
        : today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _end(DateTime first, bool month) => month
      ? DateTime.utc(
          first.year,
          first.month + 1,
        ).subtract(const Duration(days: 1))
      : first.add(const Duration(days: 6));

  Future<ActivityReport> _load(DateTime first, bool month) async {
    try {
      return await widget.auth.activityReport(
        from: first,
        to: _end(first, month),
      );
    } on AuthException catch (error) {
      if (error.sessionExpired && mounted) widget.onExpired();
      rethrow;
    }
  }

  void _chooseMode(bool month) {
    if (monthly == month || printing) return;
    setState(() {
      monthly = month;
      final current = _currentStart(month);
      start = month
          ? DateTime.utc(current.year, current.month - 1)
          : current.subtract(const Duration(days: 7));
      report = _load(start, monthly);
    });
  }

  void _move(int direction) {
    if (printing) return;
    setState(() {
      start = monthly
          ? DateTime.utc(start.year, start.month + direction)
          : start.add(Duration(days: 7 * direction));
      report = _load(start, monthly);
    });
  }

  Future<void> _refresh() async {
    final next = _load(start, monthly);
    setState(() {
      report = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder apresenta o erro e permite repetir.
    }
  }

  Future<void> _print() async {
    if (printing) return;
    final first = start;
    final month = monthly;
    setState(() => printing = true);
    try {
      final latest = await _load(first, month);
      if (!mounted) return;
      await (widget.printer ?? printActivityReport)(latest, month);
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível preparar o relatório.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  String _day(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Relatórios detalhados')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Semanal')),
                  ButtonSegment(value: true, label: Text('Mensal')),
                ],
                selected: {monthly},
                onSelectionChanged: printing
                    ? null
                    : (values) => _chooseMode(values.first),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Período anterior',
                    onPressed: printing ? null : () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_day(start)} a ${_day(_end(start, monthly))}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Período seguinte',
                    onPressed:
                        printing || !start.isBefore(_currentStart(monthly))
                        ? null
                        : () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ActivityReport>(
            future: report,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is AuthException
                    ? (snapshot.error as AuthException).message
                    : 'Não foi possível carregar o relatório.';
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(message, textAlign: TextAlign.center),
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                );
              }
              return _body(snapshot.data!);
            },
          ),
        ),
      ],
    ),
  );

  Widget _body(ActivityReport data) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Consulta: ${reportDate(data.queriedAt)} (Maputo)'),
        const SizedBox(height: 8),
        const Text(
          'Entregas e pagamentos: período selecionado. Dívidas, pedidos e estados: atuais, de todo o histórico.',
        ),
        const Text('Pagamentos marcados não comprovam recebimento externo.'),
        if (data.unknownDeliveredDates + data.unknownPaidDates > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sem data no histórico: ${reportCount(data.unknownDeliveredDates, 'entrega', 'entregas')} e ${reportCount(data.unknownPaidDates, 'pagamento', 'pagamentos')}. Não entram nos totais do período.',
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: printing ? null : _print,
          icon: const Icon(Icons.print_outlined),
          label: Text(printing ? 'A preparar...' : 'Imprimir ou guardar PDF'),
        ),
        Text(
          'A impressão consulta dados atualizados.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('Resumo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _summary(data),
        const Card(
          child: ExpansionTile(
            title: Text('Como ler o relatório'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clientes do período são os que receberam entregas.'),
                    Text('Dívida: entregas não pagas de valor positivo.'),
                    Text('Pedidos por entregar podem já estar pagos.'),
                    Text(
                      'O resumo geral inclui pedidos não pagos nas pendências.',
                    ),
                    Text('Por isso, podem ser maiores do que a dívida aqui.'),
                    Text('Pendências e estados não são um fecho histórico.'),
                    Text('Os nomes e contactos dos clientes são os atuais.'),
                    Text(
                      'Pagamentos são marcações manuais, sem comprovação de recebimento externo.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _section(
          'Clientes com entregas no período',
          reportCount(data.deliveredCustomers.length, 'cliente', 'clientes'),
          data.deliveredCustomers.length,
          (index) => _customer(data.deliveredCustomers[index], false),
          'Nenhum cliente com entrega no período.',
        ),
        _section(
          'Clientes com dívida atual',
          reportCount(data.debtCustomers.length, 'cliente', 'clientes'),
          data.debtCustomers.length,
          (index) => _customer(data.debtCustomers[index], true),
          'Nenhuma entrega pendente de pagamento.',
        ),
        _section(
          'Pedidos atualmente por entregar',
          '${reportCount(data.pendingOrders.length, 'pedido', 'pedidos')} · com ou sem pagamento',
          data.pendingOrders.length,
          (index) => _operation(data.pendingOrders[index]),
          'Nenhum pedido por entregar.',
        ),
        _section(
          'Meios de pagamento no período',
          'Distribuição pelo número de pagamentos marcados',
          data.paymentMethods.length,
          (index) =>
              _paymentMethod(data.paymentMethods[index], data.paymentMethods),
          'Nenhum meio disponível.',
        ),
        _section(
          'Pagamentos por cliente',
          '${reportCount(data.payments.length, 'pagamento', 'pagamentos')} no período',
          data.payments.length,
          (index) => _operation(data.payments[index]),
          'Nenhum pagamento marcado no período.',
        ),
        if (monthly) ...[
          _section(
            'Entregas por vendedor',
            reportCount(data.sellers.length, 'vendedor', 'vendedores'),
            data.sellers.length,
            (index) {
              final seller = data.sellers[index];
              return ListTile(
                title: Text(seller.seller),
                subtitle: Text(
                  '${reportCount(seller.operations, 'entrega', 'entregas')} · ${formatMoney(seller.amount)}',
                ),
              );
            },
            'Nenhuma entrega no período.',
          ),
          _section(
            'Vendas entregues: detalhes',
            '${reportCount(data.deliveries.length, 'venda', 'vendas')} no período',
            data.deliveries.length,
            (index) => _operation(data.deliveries[index]),
            'Nenhuma venda entregue no período.',
          ),
        ],
      ],
    ),
  );

  Widget _section(
    String title,
    String subtitle,
    int count,
    Widget Function(int) item,
    String empty,
  ) => _ReportSection(
    key: ValueKey('$title:${start.toIso8601String()}:$monthly'),
    title: title,
    subtitle: subtitle,
    count: count,
    item: item,
    empty: empty,
  );

  Widget _summary(ActivityReport data) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 290 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.6;
      final width = twoColumns
          ? (constraints.maxWidth - 8) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: width,
            child: _stat(
              Icons.local_shipping_outlined,
              'Entregas no período',
              reportCount(data.deliveries.length, 'venda', 'vendas'),
              data.deliveredAmount,
            ),
          ),
          SizedBox(
            width: width,
            child: _stat(
              Icons.payments_outlined,
              'Pagamentos no período',
              reportCount(data.payments.length, 'pagamento', 'pagamentos'),
              data.paidAmount,
            ),
          ),
          SizedBox(
            width: width,
            child: _stat(
              Icons.account_balance_wallet_outlined,
              'Dívida atual',
              reportCount(data.debtCustomers.length, 'cliente', 'clientes'),
              data.debtAmount,
            ),
          ),
          SizedBox(
            width: width,
            child: _stat(
              Icons.pending_actions_outlined,
              'Pedidos por entregar',
              reportCount(data.pendingOrders.length, 'pedido', 'pedidos'),
              data.pendingOrderAmount,
            ),
          ),
        ],
      );
    },
  );

  Widget _stat(IconData icon, String title, String count, String amount) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(count),
              Text(
                formatMoney(amount),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );

  Widget _paymentMethod(ActivityMethod method, List<ActivityMethod> all) {
    final maximum = all.fold<int>(
      0,
      (value, entry) => entry.operations > value ? entry.operations : value,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reportMethod(method.method),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${reportCount(method.operations, 'pagamento', 'pagamentos')} · ${formatMoney(method.amount)}',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: maximum == 0 ? 0 : method.operations / maximum,
            semanticsLabel:
                '${reportMethod(method.method)}: ${reportCount(method.operations, 'pagamento', 'pagamentos')}',
          ),
        ],
      ),
    );
  }

  Widget _customer(ActivityCustomer customer, bool debt) => ListTile(
    title: Text(customer.name),
    subtitle: Text(
      '${customer.phone == null ? '' : '${customer.phone}\n'}${reportCount(customer.operations, 'entrega', 'entregas')}${debt ? ' por pagar' : ''} · ${formatMoney(customer.amount)}',
    ),
  );

  Widget _operation(ActivityOperation operation) => ExpansionTile(
    title: Text(operation.customerName),
    subtitle: Text(
      '${formatMoney(operation.amount)} · Estado atual: ${reportPayment(operation)}',
    ),
    children: [
      Builder(
        builder: (context) => Column(
          children: [
            ListTile(dense: true, title: Text('Referência: ${operation.id}')),
            ListTile(
              dense: true,
              title: Text('Vendedor que registou: ${operation.seller}'),
            ),
            ListTile(
              dense: true,
              title: Text('Registo: ${reportDate(operation.createdAt)}'),
            ),
            if (operation.deliveredAt != null)
              ListTile(
                dense: true,
                title: Text('Entrega: ${reportDate(operation.deliveredAt!)}'),
              ),
            if (operation.paidAt != null)
              ListTile(
                dense: true,
                title: Text('Pagamento: ${reportDate(operation.paidAt!)}'),
              ),
            ListTile(
              dense: true,
              title: Text(
                'Estado de entrega: ${operation.deliveryStatus == 'DELIVERED'
                    ? 'Entregue'
                    : operation.deliveryStatus == 'PENDING'
                    ? 'Por entregar'
                    : 'Cancelado'}',
              ),
            ),
            if (operation.customerPhone != null)
              ListTile(
                dense: true,
                title: Text('Contacto atual: ${operation.customerPhone}'),
              ),
            if (operation.items.isEmpty)
              const ListTile(
                dense: true,
                title: Text('Sem itens disponíveis.'),
              ),
            for (final item in operation.items)
              ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text(
                  '${item.quantity} ${item.unit} · ${formatMoney(item.unitPrice)} por ${item.unit} · Total: ${formatMoney(item.lineTotal)}',
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Limita a quantidade de widgets visíveis sem omitir registos do PDF.
class _ReportSection extends StatefulWidget {
  const _ReportSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.item,
    required this.empty,
  });
  final String title;
  final String subtitle;
  final int count;
  final Widget Function(int) item;
  final String empty;

  @override
  State<_ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<_ReportSection>
    with AutomaticKeepAliveClientMixin<_ReportSection> {
  static const size = 20;
  int page = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _ReportSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (page * size >= widget.count) {
      page = widget.count == 0 ? 0 : (widget.count - 1) ~/ size;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final start = page * size;
    final end = (start + size).clamp(0, widget.count);
    final pages = (widget.count + size - 1) ~/ size;
    return Card(
      child: ExpansionTile(
        title: Text(widget.title),
        subtitle: Text(widget.subtitle),
        children: [
          if (widget.count == 0) ListTile(title: Text(widget.empty)),
          for (var i = start; i < end; i++) widget.item(i),
          if (pages > 1) ...[
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  child: const Text('Anterior'),
                ),
                Text('Página ${page + 1} de $pages'),
                TextButton(
                  onPressed: page + 1 >= pages
                      ? null
                      : () => setState(() => page++),
                  child: const Text('Seguinte'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('O PDF inclui todas as páginas.'),
            ),
          ],
        ],
      ),
    );
  }
}
