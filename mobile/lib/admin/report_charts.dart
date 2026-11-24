import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

/// Gráficos por contagem; os valores financeiros continuam na tabela do relatório.
class SalesReportCharts extends StatelessWidget {
  const SalesReportCharts({super.key, required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountChart(
          key: const ValueKey('report-events-chart'),
          title: report.periodStart == null
              ? 'Atividade no histórico'
              : 'Atividade no período',
          subtitle: 'Quantidade de eventos',
          entries: [
            _CountEntry(
              'Entregas',
              report.deliveredSales,
              colors.primary,
              'delivered',
            ),
            _CountEntry(
              'Pagamentos marcados',
              report.markedPaid,
              colors.tertiary,
              'paid',
            ),
            _CountEntry(
              'Cancelamentos',
              report.cancelledOperations,
              colors.error,
              'cancelled',
            ),
          ],
        ),
        _CountChart(
          key: const ValueKey('report-pending-chart'),
          title: 'Pendências atuais',
          subtitle: 'Todo o histórico',
          entries: [
            _CountEntry(
              'Por entregar',
              report.pendingOrders,
              colors.primary,
              'pending-orders',
            ),
            _CountEntry(
              'Por pagar',
              report.pendingPayments,
              colors.tertiary,
              'pending-payments',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            'Escalas separadas; uma operação pode aparecer mais de uma vez.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CountEntry {
  const _CountEntry(this.label, this.count, this.color, this.key);
  final String label;
  final int count;
  final Color color;
  final String key;
}

class _CountChart extends StatelessWidget {
  const _CountChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.entries,
  });
  final String title;
  final String subtitle;
  final List<_CountEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = entries.fold<int>(
      0,
      (max, entry) => entry.count > max ? entry.count : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (entries.any((entry) => entry.count < 0))
              const Text('Dados do gráfico inválidos. Atualize o relatório.')
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    container: true,
                    label: '${entry.label}: ${entry.count}',
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(entry.label)),
                              const SizedBox(width: 8),
                              Text(
                                '${entry.count}',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            key: ValueKey('report-bar-${entry.key}'),
                            value: maximum == 0 ? 0 : entry.count / maximum,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: entry.color,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
