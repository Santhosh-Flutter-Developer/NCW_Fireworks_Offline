import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/quotation/id_name.dart';
import '../models/quotation/quotation_delete_response_model.dart';
import '../models/quotation/quotation_init_response_model.dart';
import '../models/quotation/quotation_list_response_model.dart';
import '../models/quotation/quotation_product_list_response_model.dart';
import '../models/quotation/quotation_save_response_model.dart';
import '../models/quotation/quotation_selected_product_response_model.dart';

/// One product line as sent inside `product_data` on `quotation_update`.
class QuotationProductLine {
  final String productId;
  final String quantity;
  final String rate;

  const QuotationProductLine({
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

/// Talks to `quotation.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class QuotationRepository {
  QuotationRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Bootstraps the Add/Edit Quotation form: dropdown data (pricelist,
  /// party) plus — when [showQuotationId] is a real id — the existing
  /// quotation's own fields. Pass an empty string to get just the
  /// dropdown data for a brand-new quotation.
  ///
  /// Only called as a one-time backward-compat fallback now, for a
  /// quotation cached before this app version started storing full
  /// details (see [QuotationListItem.hasFullDetails]) — the normal
  /// Add/Edit flow uses [cachedPricelists]/[cachedParties]/
  /// [cachedProductsForPricelist] instead and never touches the network.
  Future<QuotationInitResponseModel> getFormInitData({
    String showQuotationId = '',
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {'show_quotation_id': showQuotationId},
    );

    final result = QuotationInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Pricelist dropdown options for the Add/Edit Quotation form —
  /// refreshed once at login and via the Sync button (see
  /// `DataSyncService._syncQuotationCatalogue`), read here with no
  /// network call.
  List<IdName> cachedPricelists() => _cache
      .getJsonList(CacheKeys.quotationPricelists)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Party dropdown options for the Add/Edit Quotation form — the same
  /// snapshot [_filterCachedQuotations] reads for its offline party
  /// filter, refreshed by [DataSyncService]'s regular quotation-list
  /// sync (every synced quotation row carries its party).
  List<IdName> cachedParties() => _cache
      .getJsonList(CacheKeys.quotationParties)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Every product offered under [pricelistId], from the full product
  /// catalogue cached at login/Sync — backs the form's product picker
  /// with no network call.
  List<QuotationProductOption> cachedProductsForPricelist(
    String pricelistId,
  ) =>
      _cache
          .getJsonList(CacheKeys.quotationProducts)
          .where((m) => m['pricelist_id']?.toString() == pricelistId)
          .map(QuotationProductOption.fromJson)
          .toList();

  /// Adds or updates one row in the on-device "pending quotation changes"
  /// queue ([CacheKeys.quotationPending]). Every add/edit from the
  /// Quotation form — draft or confirmed — goes through this, never a
  /// direct call to `quotation.php`, regardless of whether the device
  /// currently has internet. [localId] identifies the queue entry:
  /// saving under the same [localId] again (e.g. editing a not-yet-
  /// synced row a second time before syncing) replaces its previous
  /// entry instead of adding a duplicate. [editId] is the real server
  /// `quotation_id` when this is an edit of an already-synced quotation,
  /// or empty for a brand-new one. [products] carries more than the wire
  /// format needs (name/unit alongside id/qty/rate) so a pending row can
  /// be re-opened for editing without a server round trip — only
  /// id/qty/rate are actually sent once [syncPendingQuotations] runs.
  Future<void> queueQuotationForSync({
    required String localId,
    String editId = '',
    required String drafted,
    required String quotationDate, // dd-MM-yyyy
    required String pricelistId,
    String pricelistName = '',
    String agentId = '',
    required String partyId,
    String partyName = '',
    required List<Map<String, String>> products,
    String section1AddValue = '',
    String section1Discount = '',
    String section2AddValue = '',
    String section2Discount = '',
  }) async {
    final pending = _cache.getJsonList(CacheKeys.quotationPending);
    final row = <String, dynamic>{
      'local_id': localId,
      'edit_id': editId,
      'drafted': drafted,
      // Cancel stays a separate, live-only action (deleteQuotation) —
      // nothing queued here is ever cancelled.
      'cancelled': '0',
      'quotation_date': quotationDate,
      'pricelist_id': pricelistId,
      'pricelist_name': pricelistName,
      'agent_id': agentId,
      'party_id': partyId,
      'party_name': partyName,
      'product_data': products,
      'section1_add_value': section1AddValue,
      'section1_discount': section1Discount,
      'section2_add_value': section2AddValue,
      'section2_discount': section2Discount,
    };
    final updated = [
      ...pending.where((p) => p['local_id'] != localId),
      row,
    ];
    await _cache.putJsonList(CacheKeys.quotationPending, updated);
  }

  /// Removes one entry from the pending-sync queue by [localId] — used
  /// when the user deletes a row from the list before it's ever synced,
  /// so it doesn't reappear on the next reload.
  Future<void> removePendingQuotation(String localId) async {
    final pending = _cache.getJsonList(CacheKeys.quotationPending);
    await _cache.putJsonList(
      CacheKeys.quotationPending,
      pending.where((p) => p['local_id'] != localId).toList(),
    );
  }

  /// Number of quotation adds/edits saved on this device that haven't
  /// been sent to the server yet.
  int get pendingQuotationCount =>
      _cache.getJsonList(CacheKeys.quotationPending).length;

  /// Sends every queued add/edit to `quotation.php` in a single batch
  /// call — the same `quotation_update` / `quotation_data: [...]` shape
  /// the endpoint expects for multiple rows at once. Only ever called
  /// from the Sync button (via [DataSyncService]), and only while
  /// online — nothing else in the app ever calls this.
  ///
  /// On success, clears the queue. On failure (network error, or a
  /// business-rule rejection), the queue is left untouched so nothing
  /// saved on the device is lost — the next Sync attempt retries the
  /// same batch.
  Future<QuotationSaveResponseModel> syncPendingQuotations({
    required String creator,
  }) async {
    final pending = _cache.getJsonList(CacheKeys.quotationPending);
    if (pending.isEmpty) {
      return const QuotationSaveResponseModel(
        code: 200,
        message: 'Nothing to sync',
      );
    }

    final quotationData = pending.map((row) {
      final rawProducts = row['product_data'];
      final products = <Map<String, dynamic>>[
        if (rawProducts is List)
          for (final p in rawProducts)
            if (p is Map)
              {
                'product_id': p['product_id'] ?? '',
                'product_quantity': p['product_quantity'] ?? '',
                'product_rate': p['product_rate'] ?? '',
              },
      ];
      return {
        'edit_id': row['edit_id'] ?? '',
        'drafted': row['drafted'] ?? '0',
        'cancelled': row['cancelled'] ?? '0',
        'quotation_date': row['quotation_date'] ?? '',
        'pricelist_id': row['pricelist_id'] ?? '',
        'agent_id': row['agent_id'] ?? '',
        'party_id': row['party_id'] ?? '',
        'product_data': products,
        'section1_add_value': row['section1_add_value'] ?? '',
        'section1_discount': row['section1_discount'] ?? '',
        'section2_add_value': row['section2_add_value'] ?? '',
        'section2_discount': row['section2_discount'] ?? '',
      };
    }).toList();

    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {
        'quotation_update': '1',
        'creator': creator,
        'quotation_data': quotationData,
      },
    );

    final result = QuotationSaveResponseModel.fromJson(json);
    if (!result.isSuccess) {
      throw ApiRequestException(result.message);
    }

    await _cache.putJsonList(CacheKeys.quotationPending, []);
    return result;
  }

  /// Returns a page of the quotation list — always from the offline
  /// cache that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// [drafted] and [cancelled] select which tab's rows come back — pass
  /// `'1'`/`'0'` explicitly for Active / Draft / Cancel rather than
  /// leaving them blank, same as the cache is stored per-tab.
  ///
  /// The only thing that ever calls the live `quotation_listing` endpoint
  /// is a manual tap of the Sync button (`DataSyncService.syncQuotations`),
  /// which fetches the full, unpaginated list for all three tabs.
  /// Browsing the list itself never hits the network — this keeps
  /// behavior identical online and offline and means a flaky connection
  /// can never cause a half-loaded list or an unexpectedly slow screen
  /// while just looking at data.
  Future<QuotationListResponseModel> listQuotations({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    int? pageNumber,
    int? pageLimit,
    String drafted = '0',
    String cancelled = '0',
  }) async {
    return _quotationsFromCache(
      drafted: drafted,
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `quotation_listing` endpoint directly, no cache
  /// fallback. This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listQuotations] reads from. Throws on failure exactly like any
  /// other API call here; [DataSyncService] is what catches and reports
  /// it.
  Future<QuotationListResponseModel> fetchLiveQuotations({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    int? pageNumber,
    int? pageLimit,
    String drafted = '0',
    String cancelled = '0',
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {
        'quotation_listing': '1',
        'filter_from_date': filterFromDate,
        'filter_to_date': filterToDate,
        'search_text': searchText,
        'filter_party_id': filterPartyId,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
        'drafted': drafted,
        'cancelled': cancelled,
      },
    );

    final result = QuotationListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// [drafted]/[cancelled] pick which cached tab snapshot to read from —
  /// [DataSyncService] stores Active/Draft/Cancel separately, the same
  /// split the server's `drafted`/`cancelled` flags produce. Returns
  /// every cached row matching [filterFromDate]/[filterToDate]/
  /// [searchText]/[filterPartyId], unpaginated — merged with anything
  /// still sitting in the pending-sync queue that belongs to this tab.
  List<QuotationListItem> _filterCachedQuotations({
    required String drafted,
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
  }) {
    final pendingAll = _cache
        .getJsonList(CacheKeys.quotationPending)
        .map(QuotationListItem.fromPendingRow)
        .toList();

    // A pending row only shows up under the tab matching its own
    // drafted state — pending rows never carry `cancelled = 1`
    // themselves (Cancel stays a live-only action via deleteQuotation),
    // so they never appear in the Cancel tab.
    final pendingForTab = cancelled == '1'
        ? const <QuotationListItem>[]
        : pendingAll.where((q) => (q.isDraft ? '1' : '0') == drafted).toList();

    // A pending edit of an already-synced quotation (non-empty edit_id)
    // supersedes that quotation's stale synced-cache row, wherever it
    // currently sits — otherwise editing a Draft into a confirmed
    // quotation would leave a stale copy behind in the Draft tab while
    // the updated one shows in Active.
    final supersededIds =
        pendingAll.map((q) => q.quotationId).where((id) => id.isNotEmpty).toSet();

    final cacheKey = cancelled == '1'
        ? CacheKeys.quotationCancel
        : (drafted == '1' ? CacheKeys.quotationDraft : CacheKeys.quotationActive);

    final synced = _cache
        .getJsonList(cacheKey)
        .map(QuotationListItem.fromJson)
        .where((q) => !supersededIds.contains(q.quotationId))
        .toList();

    final all = [...pendingForTab.reversed, ...synced];

    final partyList = _cache
        .getJsonList(CacheKeys.quotationParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    return all.where((q) {
      if (!matchesDateRange(q.quotationDate, filterFromDate, filterToDate)) {
        return false;
      }
      // The list endpoint doesn't return a per-row party id, only the
      // combined "name / mobile / city" string, so a party filter is
      // matched by whether that string mentions the selected party's
      // name — good enough for offline browsing, not a strict id match.
      if (filterPartyId.isNotEmpty) {
        final party = partyList.where((p) => p.id == filterPartyId);
        final partyName = party.isEmpty ? null : party.first.name;
        if (partyName != null &&
            !q.partyNameMobileCity
                .toLowerCase()
                .contains(partyName.toLowerCase())) {
          return false;
        }
      }
      return matchesSearch(searchText, [
        q.quotationNumber,
        q.partyNameMobileCity,
      ]);
    }).toList();
  }

  QuotationListResponseModel _quotationsFromCache({
    required String drafted,
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final filtered = _filterCachedQuotations(
      drafted: drafted,
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
    );

    final partyList = _cache
        .getJsonList(CacheKeys.quotationParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    return QuotationListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      partyList: partyList,
      totalRecords: filtered.length,
    );
  }

  /// Products offered under a given pricelist, for the "Add Item" picker.
  Future<QuotationProductListResponseModel> getProductsForPricelist(
    String pricelistId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {'product_pricelist_id': pricelistId},
    );

    final result = QuotationProductListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Rate / unit / discount-section for one product under one pricelist —
  /// queried right after a product is picked, since
  /// `getProductsForPricelist` only returns id + name.
  Future<QuotationSelectedProductResponseModel> getSelectedProductDetail({
    required String productId,
    required String pricelistId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {
        'selected_product_id': productId,
        'pricelist_id': pricelistId,
      },
    );

    final result = QuotationSelectedProductResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Creates a new quotation, or updates an existing one when [editId] is
  /// supplied. [drafted] = `'1'` saves it as a draft (the server skips
  /// most validation and doesn't assign a bill number until it's
  /// confirmed); `'0'` is a normal create/update.
  Future<QuotationSaveResponseModel> saveQuotation({
    required String creator,
    String editId = '',
    required String drafted,
    required String quotationDate, // dd-MM-yyyy
    required String pricelistId,
    required String partyId,
    required List<QuotationProductLine> products,
    String section1AddValue = '',
    String section1Discount = '',
    String section2AddValue = '',
    String section2Discount = '',
  }) async {
    final body = <String, dynamic>{
      'quotation_update': '1',
      'creator': creator,
      'edit_id': editId,
      'drafted': drafted,
      'quotation_date': quotationDate,
      'pricelist_id': pricelistId,
      'agent_id': '',
      'party_id': partyId,
      'product_data': products.map((p) => p.toJson()).toList(),
      'section1_add_value': section1AddValue,
      'section1_discount': section1Discount,
      'section2_add_value': section2AddValue,
      'section2_discount': section2Discount,
    };

    final json = await _apiClient.postJson(ApiEndpoints.quotation, body: body);

    final result = QuotationSaveResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Deletes/cancels a quotation. The server decides which based on its
  /// own `drafted` flag: a draft is permanently deleted, anything else is
  /// marked cancelled (soft-void).
  Future<QuotationDeleteResponseModel> deleteQuotation({
    required String quotationId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.quotation,
      body: {'delete_quotation_id': quotationId},
    );

    final result = QuotationDeleteResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}