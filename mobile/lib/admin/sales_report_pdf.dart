import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/auth_service.dart';
import '../seller/seller_widgets.dart';

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

/// Usa exclusivamente os valores decimais já agregados pelo servidor.
Future<Uint8List> buildSalesReportPdf(
  SalesReport report,
  DateTime generatedAt,
  PdfPageFormat format,
) async {
  final document = pw.Document();
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoData = await rootBundle.load('assets/logo.png');
  final logo = pw.MemoryImage(
    logoData.buffer.asUint8List(logoData.offsetInBytes, logoData.lengthInBytes),
  );
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  pw.Widget paragraph(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 9),
    child: pw.Text(text),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      theme: pw.ThemeData.withFont(base: regular, bold: boldFont),
      margin: const pw.EdgeInsets.all(36),
      maxPages: 1000,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(logo, width: 56, height: 56),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Text(
                'AbigailOvos',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Relatório de vendas e pagamentos',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        paragraph(
          'Gerado em ${_date(generatedAt)}, hora do dispositivo. ${report.periodStart == null ? 'Abrange todos os eventos registados.' : 'Período dos eventos: ${report.periodStart} a ${report.periodEnd}, horário de Maputo.'}',
        ),
        paragraph(
          report.eventDatesSupported
              ? 'Entregas, pagamentos marcados e cancelamentos usam a data do respetivo evento. As pendências mostram a situação atual de todo o histórico.'
              : 'As pendências mostram a situação atual de todo o histórico.',
        ),
        if (!report.eventDatesSupported)
          paragraph(
            'Este servidor não informa datas de eventos e não suporta relatórios por período.',
          )
        else if (report.unknownDeliveredDates +
                report.unknownPaidDates +
                report.unknownCancelledDates >
            0)
          paragraph(
            'No histórico há ${report.unknownDeliveredDates} entregas, ${report.unknownPaidDates} pagamentos e ${report.unknownCancelledDates} cancelamentos sem data conhecida. ${report.periodStart == null ? 'Estão incluídos no histórico total.' : 'Não entram nos totais do período.'}',
          ),
        paragraph(
          'Foram registadas ${report.deliveredSales} vendas entregues, no valor de ${formatMoney(report.deliveredAmount)}, independentemente do estado de pagamento, e ${report.cancelledOperations} operações canceladas. Atualmente existem ${report.pendingOrders} pedidos por entregar.',
        ),
        paragraph(
          '${report.markedPaid} operações foram marcadas como pagas, no valor de ${formatMoney(report.markedPaidAmount)}. Este total inclui pedidos ainda não entregues. Marcar como pago não comprova o recebimento externo.',
        ),
        paragraph(
          'Atualmente há ${report.pendingPayments} pagamentos pendentes, no valor de ${formatMoney(report.pendingPaymentAmount)}. As pendências abrangem todo o histórico; operações canceladas ficam excluídas.',
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Vendas entregues por vendedor',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        if (report.sellers.isEmpty)
          paragraph('Ainda não há vendas entregues.')
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.3),
              2: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (final heading in ['Vendedor', 'Vendas', 'Valor'])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(heading, style: bold),
                    ),
                ],
              ),
              for (final seller in report.sellers)
                pw.TableRow(
                  children: [
                    for (final value in [
                      seller.seller,
                      '${seller.deliveredCount}',
                      formatMoney(seller.deliveredAmount),
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(value),
                      ),
                  ],
                ),
            ],
          ),
      ],
    ),
  );
  return document.save();
}

Future<bool> printSalesReport(SalesReport report, DateTime generatedAt) =>
    Printing.layoutPdf(
      name: 'Relatorio-AbigailOvos.pdf',
      onLayout: (format) => buildSalesReportPdf(report, generatedAt, format),
    );
