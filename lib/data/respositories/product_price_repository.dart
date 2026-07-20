import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/product_price_list_model.dart';

/// Talks to `product.php` for the Product Price screen. Every method
/// either returns a successful, fully-validated [ProductPriceListResponse]
/// or throws a typed [ApiException] — callers never need to check for
/// nulls or guess at error shapes.
class ProductPriceRepository {
  ProductPriceRepository({
    ApiClient? apiClient,
    ConnectivityService? connectivityService,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _connectivity = connectivityService ?? Get.find<ConnectivityService>(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final ConnectivityService _connectivity;
  final LocalCacheService _cache;

  Future<ProductPriceListResponse> fetchPriceList({
    String pricelistId = '',
    String productId = '',
    int pageNumber = 1,
    int pageLimit = 10,
  }) async {
    if (!_connectivity.isOnline.value) {
      return _priceListFromCache(
        pricelistId: pricelistId,
        productId: productId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    }

    try {
      final json = await _apiClient.postJson(
        ApiEndpoints.productPrice,
        body: {
          'product_view': '1',
          'filter_pricelist_id': pricelistId,
          'filter_product_id': productId,
          'page_number': '$pageNumber',
          'page_limit': '$pageLimit',
        },
      );

      final result = ProductPriceListResponse.fromJson(json);

      if (result.code != 200) {
        throw InvalidResponseException(
          'Server returned an unexpected status (${result.code}).',
        );
      }

      return result;
    } on NetworkException {
      return _priceListFromCache(
        pricelistId: pricelistId,
        productId: productId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    } on TimeoutApiException {
      return _priceListFromCache(
        pricelistId: pricelistId,
        productId: productId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    }
  }

  /// Rows in the cache only carry pricelist/product *names* (same as the
  /// API), not ids, so a [pricelistId]/[productId] filter is resolved to
  /// a name via the cached dropdown options first, then matched by name.
  ProductPriceListResponse _priceListFromCache({
    required String pricelistId,
    required String productId,
    required int pageNumber,
    required int pageLimit,
  }) {
    final rows = _cache
        .getJsonList(CacheKeys.priceRows)
        .map(ProductPriceRow.fromJson)
        .toList();
    final pricelists = _cache
        .getJsonList(CacheKeys.priceLists)
        .map(PricelistOption.fromJson)
        .toList();
    final products = _cache
        .getJsonList(CacheKeys.priceProducts)
        .map(ProductOption.fromJson)
        .toList();

    String? nameForId(List<dynamic> options, String id) {
      for (final o in options) {
        if (o.id == id) return o.name as String;
      }
      return null;
    }

    final pricelistName =
        pricelistId.isEmpty ? null : nameForId(pricelists, pricelistId);
    final productName =
        productId.isEmpty ? null : nameForId(products, productId);

    final filtered = rows.where((r) {
      if (pricelistName != null && r.pricelistName != pricelistName) {
        return false;
      }
      if (productName != null && r.productName != productName) {
        return false;
      }
      return true;
    }).toList();

    return ProductPriceListResponse(
      code: 200,
      rows: paginate(filtered, pageNumber, pageLimit),
      pricelists: pricelists,
      products: products,
    );
  }
}
