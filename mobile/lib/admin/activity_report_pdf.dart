import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/auth_service.dart';
import '../seller/seller_widgets.dart';

String reportMethod(String? value) => value == 'UNKNOWN' || value == null
    ? 'Não informado'
    : paymentMethodLabel(value);

String reportCount(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

String reportDate(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 2));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

String reportDay(String iso) {
  final parts = iso.split('-');
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

String reportPayment(ActivityOperation operation) =>
    operation.paymentStatus == 'PAID'
    ? 'Marcado como pago (${reportMethod(operation.paymentMethod)})'
    : 'Pagamento pendente';

/// A impressão usa a mesma resposta integral recebida do servidor.
Future<Uint8List> buildActivityReportPdf(
  ActivityReport report,
  bool monthly,
  PdfPageFormat format,
) async {
  final document = pw.Document();
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoData = await rootBundle.load('assets/logo.png');
  final logo = pw.MemoryImage(
    logoData.buffer.asUint8List(logoData.offsetInBytes, logoData.lengthInBytes),
  );
  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );
  pw.Widget paragraph(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(text),
  );
  final widgets = <pw.Widget>[
    pw.Row(
      children: [
        pw.Image(logo, width: 48, height: 48),
        pw.SizedBox(width: 12),
        pw.Text(
          'AbigailOvos',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
    heading(monthly ? 'Relatório mensal detalhado' : 'Relatório semanal'),
    paragraph(
      'Período: ${reportDay(report.periodStart)} a ${reportDay(report.periodEnd)}, horário de Maputo.',
    ),
    paragraph(
      'Consulta em ${reportDate(report.queriedAt)}, horário de Maputo. Dívidas e pedidos pendentes representam a situação atual de todo o histórico, não o estado no fim do período.',
    ),
    paragraph(
      'As compras correspondem a entregas no período. As dívidas incluem apenas entregas de valor positivo ainda não pagas; pedidos por entregar aparecem separadamente, pagos ou não.',
    ),
    paragraph(
      'O resumo geral inclui também pedidos por entregar não pagos em pagamentos pendentes, pelo que esse valor pode ser maior do que a dívida aqui apresentada.',
    ),
    paragraph(
      'Os pagamentos são marcações manuais e não comprovam recebimento externo. Os nomes e contactos dos clientes são os atuais.',
    ),
    paragraph(
      'Total de entregas no período: ${formatMoney(report.deliveredAmount)}. Pagamentos marcados no período: ${formatMoney(report.paidAmount)}.',
    ),
    paragraph(
      'Dívida atual de entregas: ${formatMoney(report.debtAmount)}. Valor total dos pedidos por entregar: ${formatMoney(report.pendingOrderAmount)} (podem já estar pagos).',
    ),
    if (report.unknownDeliveredDates + report.unknownPaidDates > 0)
      paragraph(
        'Datas desconhecidas no histórico: ${reportCount(report.unknownDeliveredDates, 'entrega', 'entregas')} e ${reportCount(report.unknownPaidDates, 'pagamento', 'pagamentos')}. Não entram nos totais por período.',
      ),
    heading(
      'Clientes com entregas no período (${report.deliveredCustomers.length})',
    ),
    if (report.deliveredCustomers.isEmpty)
      paragraph('Nenhum cliente com entrega no período.'),
    for (final customer in report.deliveredCustomers)
      paragraph(
        '${customer.name}${customer.phone == null ? '' : ' · ${customer.phone}'}: ${reportCount(customer.operations, 'entrega', 'entregas')}, ${formatMoney(customer.amount)}.',
      ),
    heading('Clientes com dívida atual (${report.debtCustomers.length})'),
    if (report.debtCustomers.isEmpty)
      paragraph('Nenhuma entrega pendente de pagamento.'),
    for (final customer in report.debtCustomers)
      paragraph(
        '${customer.name}${customer.phone == null ? '' : ' · ${customer.phone}'}: ${reportCount(customer.operations, 'entrega', 'entregas')} por pagar, ${formatMoney(customer.amount)}.',
      ),
    heading('Pedidos atualmente por entregar (${report.pendingOrders.length})'),
    if (report.pendingOrders.isEmpty) paragraph('Nenhum pedido por entregar.'),
    for (final order in report.pendingOrders) ...[
      paragraph(
        '${order.customerName}${order.customerPhone == null ? '' : ' · ${order.customerPhone}'}: ${formatMoney(order.amount)} · ${reportPayment(order)}. Vendedor que registou: ${order.seller}. Registado em ${reportDate(order.createdAt)}.',
      ),
      if (monthly)
        for (final item in order.items)
          paragraph(
            '  ${item.name}: ${item.quantity} ${item.unit}, ${formatMoney(item.unitPrice)} por ${item.unit}, total ${formatMoney(item.lineTotal)}.',
          ),
    ],
    heading('Meios dos pagamentos marcados no período'),
    for (final method in report.paymentMethods)
      paragraph(
        '${reportMethod(method.method)}: ${reportCount(method.operations, 'pagamento', 'pagamentos')}, ${formatMoney(method.amount)}.',
      ),
    heading('Pagamentos marcados por cliente (${report.payments.length})'),
    if (report.payments.isEmpty)
      paragraph('Nenhum pagamento marcado no período.'),
    for (final payment in report.payments)
      paragraph(
        '${payment.customerName}${payment.customerPhone == null ? '' : ' · ${payment.customerPhone}'}: ${formatMoney(payment.amount)}, ${reportMethod(payment.paymentMethod)}, ${payment.paidAt == null ? 'data desconhecida' : reportDate(payment.paidAt!)}. Vendedor que registou a operação: ${payment.seller}.',
      ),
    if (monthly) ...[
      heading('Entregas por vendedor'),
      if (report.sellers.isEmpty) paragraph('Nenhuma entrega no período.'),
      for (final seller in report.sellers)
        paragraph(
          '${seller.seller}: ${reportCount(seller.operations, 'entrega', 'entregas')}, ${formatMoney(seller.amount)}.',
        ),
      heading(
        'Vendas entregues no período: detalhes (${report.deliveries.length})',
      ),
      if (report.deliveries.isEmpty)
        paragraph('Nenhuma venda entregue no período.'),
      for (final sale in report.deliveries) ...[
        paragraph(
          '${sale.customerName} · ${formatMoney(sale.amount)} · vendedor que registou: ${sale.seller} · referência: ${sale.id}.',
        ),
        paragraph(
          '  Registo: ${reportDate(sale.createdAt)} · entrega: ${sale.deliveredAt == null ? 'data desconhecida' : reportDate(sale.deliveredAt!)} · estado atual: ${reportPayment(sale)}${sale.paidAt == null ? '' : ', ${reportDate(sale.paidAt!)}'}.',
        ),
        for (final item in sale.items)
          paragraph(
            '  ${item.name}: ${item.quantity} ${item.unit}, ${formatMoney(item.unitPrice)} por ${item.unit}, total ${formatMoney(item.lineTotal)}.',
          ),
      ],
    ],
  ];
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(36),
      maxPages: 1000,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => widgets,
    ),
  );
  return document.save();
}

Future<bool> printActivityReport(ActivityReport report, bool monthly) =>
    Printing.layoutPdf(
      name: monthly
          ? 'Relatorio-mensal-AbigailOvos.pdf'
          : 'Relatorio-semanal-AbigailOvos.pdf',
      onLayout: (format) => buildActivityReportPdf(report, monthly, format),
    );
