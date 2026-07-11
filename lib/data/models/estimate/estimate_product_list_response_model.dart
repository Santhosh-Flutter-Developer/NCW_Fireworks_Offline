import '../../../core/network/api_exception.dart';

/// One product option offered for a given pricelist — id/name only.
/// Rate, unit and stock aren't known until [selected_product_id] is
/// queried for this specific product + pricelist combination.
class EstimateProductOption {
  final String productId;
  final String productName;

  const EstimateProductOption({
    required this.productId,
    required this.productName,
  });

  factory EstimateProductOption.fromJson(Map<String, dynamic> json) {
    return EstimateProductOption(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a
/// `product_pricelist_id` call.
class EstimateProductListResponseModel {
  final int code;
  final String message;
  final List<EstimateProductOption> products;

  const EstimateProductListResponseModel({
    required this.code,
    required this.message,
    required this.products,
  });

  bool get isSuccess => code == 200;

  factory EstimateProductListResponseModel.fromJson(
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

    final products = <EstimateProductOption>[];
    final rawList = head['product_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          products.add(
              EstimateProductOption.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    return EstimateProductListResponseModel(
      code: code,
      message: message,
      products: products,
    );
  }
}
