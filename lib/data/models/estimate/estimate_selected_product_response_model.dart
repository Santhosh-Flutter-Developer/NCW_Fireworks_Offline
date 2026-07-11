import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// Parses the `{"head": {...}}` envelope returned for a
/// `selected_product_id` call — the rate/unit/stock lookup fired once a
/// product is chosen for a given pricelist.
class EstimateSelectedProductResponseModel {
  final int code;
  final String message;
  final String unitId;
  final String unitName;
  final double rate;

  /// `1` when this product/pricelist combination has the discount flag
  /// set — matches the server's own rule for which totals section (1 or
  /// 2) the line lands in once saved.
  final bool productDiscount;
  final int currentStock;

  const EstimateSelectedProductResponseModel({
    required this.code,
    required this.message,
    required this.unitId,
    required this.unitName,
    required this.rate,
    required this.productDiscount,
    required this.currentStock,
  });

  bool get isSuccess => code == 200;

  factory EstimateSelectedProductResponseModel.fromJson(
      Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final rawCode = head['code'];
    final code = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;

    final rawMsg = head['msg'];
    final message = (rawMsg is String && rawMsg.trim().isNotEmpty)
        ? rawMsg.trim()
        : 'Unexpected response from server.';

    return EstimateSelectedProductResponseModel(
      code: code,
      message: message,
      unitId: head['unit_id']?.toString() ?? '',
      unitName: head['unit_name']?.toString() ?? '',
      rate: readNum(head['rate']),
      productDiscount: head['product_discount']?.toString() == '1',
      currentStock: readIntSafe(head['current_stock']),
    );
  }
}
