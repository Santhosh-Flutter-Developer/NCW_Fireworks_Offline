import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:ncw_fireworks/data/models/billing_item_model.dart';
import 'package:ncw_fireworks/data/models/party/party_list_response_model.dart';
import 'package:ncw_fireworks/data/models/quotation_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'company_profile.dart';
import 'indian_currency_words.dart';

/// Builds the A4 quotation PDF entirely on-device from data already
/// cached/queued locally (the quotation itself, plus its party's full
/// details — see `PartyRepository.cachedPartyById`) — no network call,
/// so Print and Download both work the same whether the device is
/// online or not, and whether or not the quotation has been synced yet.
///
/// Mirrors the layout of the server's own `rpt_quotation_a4.php` report:
/// centered title + letterhead, a bordered two-column "Bill To" /
/// "Bill Date, Bill No, HSN Code" box, a product table with a grey
/// header row, per-section subtotal/add/discount rows when a section
/// has any, a combined Total Quantity + Sub Total row, Round Off, Bill
/// Total, "Amount in words", and a Declaration/signature footer.
class QuotationPdfBuilder {
  static const _greenLabel = PdfColor.fromInt(0xFF008200); // rgb(0,130,0)
  static const _headerFill = PdfColor.fromInt(0xFF65727A); // rgb(101,114,122)
  static const _borderColor = PdfColor.fromInt(0xFF000000);
  static final _dateFormat = DateFormat('dd-MM-yyyy');
  static final _numberFormat = NumberFormat('#,##0.00', 'en_IN');

  static Future<Uint8List> build({
    required QuotationModel quotation,
    PartyListItem? party,
  }) async {
    final doc = pw.Document(title: 'Quotation');
    final isCancelled = quotation.status == DocStatus.cancelled;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 10 * PdfPageFormat.mm,
          marginRight: 10 * PdfPageFormat.mm,
          marginTop: 5 * PdfPageFormat.mm,
          marginBottom: 10 * PdfPageFormat.mm,
        ),
        header: (context) => _buildHeader(quotation, party),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          if (isCancelled) _buildCancelledStamp(),
          _buildProductTable(quotation),
          _buildTotals(quotation),
          pw.SizedBox(height: 6),
          _buildDeclarationAndSignature(quotation),
        ],
      ),
    );

    return doc.save();
  }

  // ---- Header: title + letterhead + Bill To / Bill Date box ----------

  static pw.Widget _buildHeader(
    QuotationModel quotation,
    PartyListItem? party,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'Quotation',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                CompanyProfile.name,
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              for (final line in CompanyProfile.addressLines)
                pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Contact : ${CompanyProfile.contactNumber}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('GST : ${CompanyProfile.gstNumber}',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 0.5)),
                padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 3),
                child: _buildBillTo(party),
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 0.5)),
                padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 3),
                child: _buildBillMeta(quotation),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildBillTo(PartyListItem? party) {
    // Mirrors the server's own rule: the party's own snapshot is a list
    // of non-empty lines (name first, bold; the rest smaller) — built
    // here from the cached party record instead of a pre-baked string.
    final lines = <String>[];
    if (party != null) {
      if (party.partyName.isNotEmpty) lines.add(party.partyName);
      if (party.address.isNotEmpty) lines.add(party.address);
      final cityLine =
          [party.city, party.district].where((s) => s.isNotEmpty).join(', ');
      if (cityLine.isNotEmpty) lines.add(cityLine);
      if (party.state.isNotEmpty) lines.add(party.state);
      if (party.pincode.isNotEmpty) lines.add(party.pincode);
      if (party.mobileNumber.isNotEmpty) lines.add(party.mobileNumber);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Bill To :',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        if (lines.isEmpty)
          pw.Text('Direct', style: const pw.TextStyle(fontSize: 8))
        else ...[
          pw.Text(lines.first,
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final line in lines.skip(1))
            pw.Text(line, style: const pw.TextStyle(fontSize: 8)),
        ],
      ],
    );
  }

  static pw.Widget _buildBillMeta(QuotationModel quotation) {
    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 62,
                child: pw.Text(label,
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _greenLabel)),
              ),
              pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
              pw.Expanded(
                child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        row('Bill Date', _dateFormat.format(quotation.date)),
        row('Bill No', quotation.quotationNo),
        row('HSN Code', '3604'),
      ],
    );
  }

  // ---- Cancelled watermark ---------------------------------------------

  static pw.Widget _buildCancelledStamp() {
    return pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          right: 0,
          top: 40,
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: 0.5,
              child: pw.Opacity(
                opacity: 0.25,
                child: pw.Text(
                  'CANCELLED',
                  style: pw.TextStyle(
                    fontSize: 60,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Product table --------------------------------------------------

  static pw.Widget _buildProductTable(QuotationModel quotation) {
    final headerStyle = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );
    final cellStyle = const pw.TextStyle(fontSize: 8);

    pw.Widget headerCell(String text, pw.TextAlign align) => pw.Container(
          color: _headerFill,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: pw.Text(text, style: headerStyle, textAlign: align),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        headerCell('S.No', pw.TextAlign.center),
        headerCell('Product', pw.TextAlign.center),
        headerCell('Qty', pw.TextAlign.center),
        headerCell('Rate(Rs.)', pw.TextAlign.center),
        headerCell('Amount(Rs.)', pw.TextAlign.center),
      ]),
    ];

    var index = 1;
    for (final item in quotation.items) {
      rows.add(
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: pw.Text('${index++}',
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: pw.Text(' ${item.productName}', style: cellStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: pw.Text('${item.quantity} ${item.unit}',
                style: cellStyle, textAlign: pw.TextAlign.center),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: pw.Text(_numberFormat.format(item.rate),
                style: cellStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: pw.Text(_numberFormat.format(item.amount),
                style: cellStyle, textAlign: pw.TextAlign.right),
          ),
        ]),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.5),
        1: pw.FlexColumnWidth(5.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.35),
        4: pw.FlexColumnWidth(1.35),
      },
      children: rows,
    );
  }

  // ---- Totals: per-section add/discount, then combined summary -------

  static pw.Widget _buildTotals(QuotationModel quotation) {
    final widgets = <pw.Widget>[];

    final sections = [
      (quotation.section1Items, quotation.section1Total, quotation.section1Add,
          quotation.section1Discount),
      (quotation.section2Items, quotation.section2Total, quotation.section2Add,
          quotation.section2Discount),
    ];

    for (final (items, sectionTotal, addValue, discountValue) in sections) {
      if (items.isEmpty) continue;
      widgets.add(_totalRow('Sub Total', sectionTotal));
      if (addValue > 0) widgets.add(_totalRow('Add', addValue));
      if (discountValue > 0) widgets.add(_totalRow('Discount', discountValue));
      if (addValue > 0 || discountValue > 0) {
        widgets.add(
            _totalRow('Total', sectionTotal + addValue - discountValue));
      }
    }

    // Combined summary: Total Quantity (left) + Sub Total (right) on one
    // row, then Round Off, then Bill Total — matches the server report.
    widgets.add(
      pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              alignment: pw.Alignment.centerRight,
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(color: _borderColor, width: 0.5),
                  top: pw.BorderSide(color: _borderColor, width: 0.5),
                  bottom: pw.BorderSide(color: _borderColor, width: 0.5),
                ),
              ),
              child: pw.Text('Total Quantity',
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _greenLabel)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text('${quotation.totalQty} Pcs',
                  style: const pw.TextStyle(fontSize: 8)),
            ),
          ),
          pw.Container(
            width: 90,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text('Sub Total',
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
          ),
          pw.Container(
            width: 90,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text(_numberFormat.format(quotation.subTotal),
                style: const pw.TextStyle(fontSize: 8)),
          ),
        ],
      ),
    );
    widgets.add(_totalRow('Round Off', quotation.roundOff));
    widgets.add(_totalRow('Bill Total', quotation.total, bold: true));

    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderColor, width: 0.5)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Amount in words : ',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
            pw.Expanded(
              child: pw.Text(IndianCurrencyWords.convert(quotation.total),
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Text('E. & O.E', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: widgets);
  }

  static pw.Widget _totalRow(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text(label,
                style: style.copyWith(
                    fontWeight: pw.FontWeight.bold, color: _greenLabel)),
          ),
        ),
        pw.Container(
          width: 90,
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 0.5)),
          child: pw.Text(_numberFormat.format(value), style: style),
        ),
      ],
    );
  }

  // ---- Declaration + signature ----------------------------------------

  static pw.Widget _buildDeclarationAndSignature(QuotationModel quotation) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 12,
          child: pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Declaration : ',
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greenLabel)),
                pw.Text(
                  'We declare that this bill shows the actual price of the '
                  'goods described and that all particulars are true and '
                  'correct.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ),
        pw.Expanded(
          flex: 7,
          child: pw.Container(
            height: 45,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('For ${CompanyProfile.name}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greenLabel)),
                pw.Text('Authorised Signatory',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Footer -----------------------------------------------------------

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '*** This is a Computer Generated bill. Hence Digital Signature is not required. ***',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page No : ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],
    );
  }
}