import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One product option offered for a given pricelist.
///
/// `product_pricelist_id` actually returns rate/unit/discount-flag/stock
/// alongside id+name for every row (verified against the live API
/// response), so they're parsed here too — this lets the product picker
/// show price up front, without a `selected_product_id` round-trip per
/// product.
class QuotationProductOption {
  final String productId;
  final String productName;
  final String unitId;
  final String unitName;
  final double rate;

  /// `true` when this product/pricelist combination has the discount flag
  /// set — matches the server's own rule for which totals section (1 or
  /// 2) the line lands in once saved.
  final bool productDiscount;

  /// Present on the list response, but quotations don't reserve stock the
  /// way estimates do — kept for parity/display only, may read as 0.
  final int currentStock;

  const QuotationProductOption({
    required this.productId,
    required this.productName,
    this.unitId = '',
    this.unitName = '',
    this.rate = 0,
    this.productDiscount = false,
    this.currentStock = 0,
  });

  factory QuotationProductOption.fromJson(Map<String, dynamic> json) {
    return QuotationProductOption(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      unitId: json['unit_id']?.toString() ?? '',
      unitName: json['unit_name']?.toString() ?? '',
      rate: readNum(json['rate']),
      productDiscount: json['product_discount']?.toString() == '1',
      currentStock: readIntSafe(json['current_stock']),
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a
/// `product_pricelist_id` call.
class QuotationProductListResponseModel {
  final int code;
  final String message;
  final List<QuotationProductOption> products;

  const QuotationProductListResponseModel({
    required this.code,
    required this.message,
    required this.products,
  });

  bool get isSuccess => code == 200;

  factory QuotationProductListResponseModel.fromJson(
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

    final products = <QuotationProductOption>[];
    final rawList = head['product_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          products.add(QuotationProductOption.fromJson(
              Map<String, dynamic>.from(row)));
        }
      }
    }

    return QuotationProductListResponseModel(
      code: code,
      message: message,
      products: products,
    );
  }
}