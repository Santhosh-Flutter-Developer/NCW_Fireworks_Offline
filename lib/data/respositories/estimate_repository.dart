import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/estimate/estimate_charge_type_response_model.dart';
import '../models/estimate/estimate_init_response_model.dart';
import '../models/estimate/estimate_list_response_model.dart';
import '../models/estimate/estimate_product_list_response_model.dart';
import '../models/estimate/estimate_save_response_model.dart';
import '../models/estimate/estimate_selected_product_response_model.dart';

/// One product line as sent inside `product_data` on `estimate_update`.
class EstimateProductLine {
  final String productId;
  final String quantity;
  final String rate;

  const EstimateProductLine({
    required this.productId,
    required this.quantity,
    required this.rate,
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_quantity': quantity,
        'product_rate': rate,
      };
}

/// One other-charge line, sent as three parallel arrays
/// (`other_charges_id` / `other_charges_type` / `other_charges_value`) on
/// `estimate_update`.
class EstimateChargeLine {
  final String chargeId;
  final String type; // "Plus" or "Minus"
  final String value;

  const EstimateChargeLine({
    required this.chargeId,
    required this.type,
    required this.value,
  });
}

/// Talks to `estimate.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class EstimateRepository {
  EstimateRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Bootstraps the Add/Edit Estimate form: dropdown data (pricelist,
  /// agent, party, other charges) plus — when [showEstimateId] is a real
  /// id — the existing estimate's own fields. Pass an empty string to get
  /// just the dropdown data for a brand-new estimate.
  Future<EstimateInitResponseModel> getFormInitData({
    String showEstimateId = '',
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'show_estimate_id': showEstimateId},
    );

    final result = EstimateInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Fetches a page of the estimate list, with the same From/To/search/
  /// agent/party filters as the web app's Estimate list screen.
  Future<EstimateListResponseModel> listEstimates({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterAgentId = '',
    String filterPartyId = '',
    int pageNumber = 1,
    int pageLimit = 10,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'estimate_listing': '1',
        'filter_from_date': filterFromDate,
        'filter_to_date': filterToDate,
        'search_text': searchText,
        'filter_agent_id': filterAgentId,
        'filter_party_id': filterPartyId,
        'page_number': pageNumber.toString(),
        'page_limit': pageLimit.toString(),
      },
    );

    final result = EstimateListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Products offered under a given pricelist, for the "Add Item" picker.
  Future<EstimateProductListResponseModel> getProductsForPricelist(
    String pricelistId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'product_pricelist_id': pricelistId},
    );

    final result = EstimateProductListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Rate / unit / current stock / discount-section for one product under
  /// one pricelist — queried right after a product is picked, since
  /// `getProductsForPricelist` only returns id + name.
  Future<EstimateSelectedProductResponseModel> getSelectedProductDetail({
    required String productId,
    required String pricelistId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'selected_product_id': productId,
        'pricelist_id': pricelistId,
      },
    );

    final result = EstimateSelectedProductResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Whether a chosen other-charge is added ("Plus") or deducted
  /// ("Minus"), looked up right after it's picked from the dropdown.
  Future<EstimateChargeTypeResponseModel> getChargeType(
    String otherChargesId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'type_other_charges_id': otherChargesId},
    );

    final result = EstimateChargeTypeResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Creates a new estimate, or updates an existing one when [editId] is
  /// supplied.
  Future<EstimateSaveResponseModel> saveEstimate({
    required String creator,
    String editId = '',
    required String estimateDate, // dd-MM-yyyy
    required String pricelistId,
    String agentId = '',
    required String partyId,
    required List<EstimateProductLine> products,
    String section1AddValue = '',
    String section1Discount = '',
    String section2AddValue = '',
    String section2Discount = '',
    List<EstimateChargeLine> charges = const [],
  }) async {
    final body = <String, dynamic>{
      'estimate_update': '1',
      'creator': creator,
      'edit_id': editId,
      'estimate_date': estimateDate,
      'pricelist_id': pricelistId,
      'agent_id': agentId,
      'party_id': partyId,
      'product_data': products.map((p) => p.toJson()).toList(),
      'section1_add_value': section1AddValue,
      'section1_discount': section1Discount,
      'section2_add_value': section2AddValue,
      'section2_discount': section2Discount,
      'other_charges_id': charges.map((c) => c.chargeId).toList(),
      'other_charges_type': charges.map((c) => c.type).toList(),
      'other_charges_value': charges.map((c) => c.value).toList(),
    };

    final json = await _apiClient.postJson(ApiEndpoints.estimate, body: body);

    final result = EstimateSaveResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}
