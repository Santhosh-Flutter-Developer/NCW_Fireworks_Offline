import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/party/party_detail_response_model.dart';
import '../models/party/party_list_response_model.dart';
import '../models/party/party_save_response_model.dart';

/// Talks to `party.php`. Mirrors [AuthRepository]'s contract: every method
/// either returns a successful, validated result or throws a typed
/// [ApiException] — callers never need to inspect raw response maps.
class PartyRepository {
  PartyRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

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

  /// Fetches a page of the party list. [agentId] is always sent as an
  /// empty string for now — there's no agent filter in the UI — and
  /// [searchText] matches by party name.
  Future<PartyListResponseModel> listParties({
    String agentId = '',
    String searchText = '',
    int pageNumber = 1,
    int pageLimit = 10,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {
        'party_listing': '1',
        'filter_agent_id': agentId,
        'search_text': searchText,
        'page_number': pageNumber.toString(),
        'page_limit': pageLimit.toString(),
      },
    );

    final result = PartyListResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    throw ApiRequestException(result.message);
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
