import '../../../core/access/sectors.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../domain/models.dart';

Future<Uint8List> reportPdf(
  List<ReportRow> rows, {
  required String synchronization,
}) async {
  final document = pw.Document();
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final total = rows
      .where((r) => r.consumption.status == 'confirmed')
      .fold<int>(0, (n, r) => n + r.item.totalCents);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 500,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Consumo interno',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Relatório de consumo interno',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(synchronization, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 14),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}'),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: [
            'Data',
            'Código',
            'Produto',
            'UN/KG',
            'Quantidade',
            'Total R\$',
            'Setor',
            'Responsável',
            'Situação',
          ],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          data: rows
              .map(
                (r) => [
                  r.consumption.date,
                  r.item.code,
                  r.item.description,
                  r.item.unit,
                  quantity(r.item.amount, r.item.unit),
                  money(r.item.totalCents),
                  sectorLabel(
                    r.consumption.assignedSector ?? r.consumption.sector,
                  ),
                  r.consumption.operatorName,
                  r.consumption.status == 'confirmed'
                      ? 'Confirmado'
                      : 'Cancelado',
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Total dos itens confirmados: ${money(total)}'),
        pw.Text(
          'Cancelamentos, quando selecionados, são exibidos para conferência; não representam consumo válido.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
  return document.save();
}
