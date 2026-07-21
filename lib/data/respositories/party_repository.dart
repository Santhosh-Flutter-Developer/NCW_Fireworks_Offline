import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/party/party_detail_response_model.dart';
import '../models/party/party_list_response_model.dart';
import '../models/party/party_save_response_model.dart';

/// Talks to `party.php`. Mirrors [AuthRepository]'s contract: every method
/// either returns a successful, validated result or throws a typed
/// [ApiException] — callers never need to inspect raw response maps.
class PartyRepository {
  PartyRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Creates a new party, or updates an existing one when [editId] is
  /// supplied. All optional fields are sent as empty strings when unset,
  /// matching what the API expects (it treats blank as "not provided") —
  /// except [othersCity], which the API only wants when [city] is
  /// literally `"Others"`; the `others_city` key is omitted entirely
  /// otherwise.
  Future<PartySaveResponseModel> createOrUpdateParty({
    required String creator,
    required String partyName,
    String editId = '',
    String agentId = '',
    String mobileNumber = '',
    String email = '',
    String identification = '',
    String address = '',
    required String state,
    String district = '',
    String city = '',
    String? othersCity,
    String pincode = '',
    String gstNumber = '',
    String openingBalance = '',
    String openingBalanceType = '',
  }) async {
    final body = <String, dynamic>{
      'party_update': '1',
      'creator': creator,
      'party_name': partyName,
      'edit_id': editId,
      'agent_id': agentId,
      'mobile_number': mobileNumber,
      'email': email,
      'identification': identification,
      'address': address,
      'state': state,
      'district': district,
      'city': city,
      'pincode': pincode,
      'gst_number': gstNumber,
      'opening_balance': openingBalance,
      'opening_balance_type': openingBalanceType,
    };
    if (othersCity != null && othersCity.isNotEmpty) {
      body['others_city'] = othersCity;
    }

    final json = await _apiClient.postJson(ApiEndpoints.party, body: body);

    final result = PartySaveResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    // Every non-200 head.code from this endpoint is a business/validation
    // rejection with an already user-presentable message (duplicate name,
    // duplicate mobile, invalid agent, invalid creator, etc).
    throw ApiRequestException(result.message);
  }

  /// Returns a page of the party list — always from the offline cache
  /// that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// The only thing that ever calls the live `party_listing` endpoint is
  /// a manual tap of the Sync button (`DataSyncService.syncParty`), which
  /// fetches the full, unpaginated list. Browsing the list itself never
  /// hits the network — this keeps behavior identical online and offline
  /// and means a flaky connection can never cause a half-loaded list or
  /// an unexpectedly slow screen while just looking at data.
  ///
  /// [agentId] is accepted for API-shape compatibility but currently
  /// unused — there's no agent filter in the UI, and the cached rows
  /// don't carry an agent id to filter by anyway.
  Future<PartyListResponseModel> listParties({
    String agentId = '',
    String searchText = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    return _partiesFromCache(
      searchText: searchText,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `party_listing` endpoint directly, no cache fallback.
  /// This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listParties] reads from. Throws on failure exactly like any other
  /// API call here; [DataSyncService] is what catches and reports it.
  Future<PartyListResponseModel> fetchLiveParties({
    String agentId = '',
    String searchText = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {
        'party_listing': '1',
        'filter_agent_id': agentId,
        'search_text': searchText,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
      },
    );

    final result = PartyListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Builds a page of results from whatever [DataSyncService] last cached,
  /// applying the same name search the server would. There's no
  /// agent-id field on the cached rows (the list endpoint never returns
  /// one), so an [agentId] filter can't be honored offline — matches
  /// today's UI, which never sets one anyway.
  PartyListResponseModel _partiesFromCache({
    required String searchText,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final all = _cache
        .getJsonList(CacheKeys.party)
        .map(PartyListItem.fromJson)
        .toList();

    final filtered = all
        .where((p) => matchesSearch(searchText, [p.partyName]))
        .toList();

    return PartyListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      totalRecords: filtered.length,
    );
  }

  /// Fetches full details for one party, used to hydrate the Edit form
  /// before saving — the list endpoint only returns id/name/state.
  Future<PartyDetailResponseModel> getPartyDetail(String partyId) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {'show_party_id': partyId},
    );

    final result = PartyDetailResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    throw ApiRequestException(result.message);
  }
}