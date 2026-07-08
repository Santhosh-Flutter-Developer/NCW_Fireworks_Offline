import 'billing_item_model.dart';

class QuotationModel {
  final String id;
  final String quotationNo;
  String partyId;
  String partyName;
  String agentName;
  String pricelistName;
  DateTime date;
  DateTime validTill;
  List<BillingItemModel> items;
  DocStatus status;
  String notes;

  /// Manual add/discount values applied on top of each section's subtotal,
  /// mirroring the "Add:" / "Discount:" fields under Section 1 / Section 2
  /// on the web app's Add Quotation screen.
  double section1Add;
  double section1Discount;
  double section2Add;
  double section2Discount;
  double roundOff;

  QuotationModel({
    required this.id,
    required this.quotationNo,
    required this.partyId,
    required this.partyName,
    this.agentName = 'Direct',
    this.pricelistName = '',
    required this.date,
    required this.validTill,
    required this.items,
    this.status = DocStatus.draft,
    this.notes = '',
    this.section1Add = 0,
    this.section1Discount = 0,
    this.section2Add = 0,
    this.section2Discount = 0,
    this.roundOff = 0,
  });

  List<BillingItemModel> get section1Items =>
      items.where((i) => i.section == 1).toList();
  List<BillingItemModel> get section2Items =>
      items.where((i) => i.section == 2).toList();

  double get section1Total =>
      section1Items.fold(0, (sum, i) => sum + i.amount);
  double get section2Total =>
      section2Items.fold(0, (sum, i) => sum + i.amount);

  double get subTotal => section1Total + section2Total;
  double get adjustments =>
      (section1Add - section1Discount) + (section2Add - section2Discount);
  double get total => subTotal + adjustments + roundOff;

  /// Kept for screens/dashboards that only care about the grand total.
  double get grandTotal => total;

  int get totalQty => items.fold(0, (sum, i) => sum + i.quantity);

  /// e.g. "125 Case" — matches the "Bill Qty" column on the web app.
  String get qtyLabel {
    if (items.isEmpty) return '0';
    final unit = items.first.unit.isNotEmpty ? items.first.unit : 'Pcs';
    return '$totalQty $unit';
  }
}
