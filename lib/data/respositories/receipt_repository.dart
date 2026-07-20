import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/receipt/id_name.dart';
import '../models/receipt/receipt_balance_response_model.dart';
import '../models/receipt/receipt_bank_response_model.dart';
import '../models/receipt/receipt_bill_lookup_response_model.dart';
import '../models/receipt/receipt_form_init_response_model.dart';
import '../models/receipt/receipt_list_response_model.dart';
import '../models/receipt/receipt_save_response_model.dart';

/// One payment-mode/bank/amount line, as sent inside the parallel
/// `payment_mode_id` / `bank_id` / `amount` arrays on `receipt_update`.
class ReceiptPaymentEntry {
  final String paymentModeId;

  /// Sent verbatim, including `""` for cash-style modes — the server
  /// expects one array slot per payment line either way (see the
  /// Postman example: `bank_id: ["", "<real id>"]`).
  final String bankId;
  final String amount;

  const ReceiptPaymentEntry({
    required this.paymentModeId,
    required this.bankId,
    required this.amount,
  });
}

/// Talks to `receipt.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class ReceiptRepository {
  ReceiptRepository({
    ApiClient? apiClient,
    ConnectivityService? connectivityService,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _connectivity = connectivityService ?? Get.find<ConnectivityService>(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final ConnectivityService _connectivity;
  final LocalCacheService _cache;

  /// Bootstraps the Add Receipt form: today's default receipt date plus
  /// the Payment Mode dropdown options. There's no "load an existing
  /// receipt" mode — Receipts are create-or-delete only.
  Future<ReceiptFormInitResponseModel> getFormInitData() async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'show_receipt_id': ''},
    );

    final result = ReceiptFormInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Banks linked to a chosen payment mode, for the Bank dropdown. An
  /// empty list back (still `code == 200`) means this mode is cash-style
  /// and has no bank of its own — see [ReceiptBankResponseModel].
  Future<ReceiptBankResponseModel> getBanksForPaymentMode(
    String paymentModeId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'selected_bank_payment_mode': paymentModeId},
    );

    final result = ReceiptBankResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Looks up an active bill (estimate) by its printed number, for the
  /// "Bill Number" field on Billwise Payment. Throws with the server's
  /// own message (`"Empty Estimate"` / `"Invalid Estimate"`) when not
  /// found, so the form can show it inline under the field.
  Future<ReceiptBillLookupResponseModel> lookupBill(String billNumber) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'payment_bill_number': billNumber},
    );

    final result = ReceiptBillLookupResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Current balance for a chosen payment mode/bank/account — the
  /// "Account Balance : ..." helper text shown next to the Amount field.
  Future<ReceiptBalanceResponseModel> getAccountBalance(
    String accountBalanceId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'account_balance_id': accountBalanceId},
    );

    final result = ReceiptBalanceResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Paginated, filtered Receipt list — mirrors the columns/filters on
  /// the web app's Receipt screen (from/to date, receipt number search,
  /// party, Active/Cancel). [pageNumber]/[pageLimit] are optional: leave
  /// them null (as [DataSyncService] does) to fetch the unpaginated full
  /// list, with no `page_number`/`page_limit` sent at all.
  Future<ReceiptListResponseModel> listReceipts({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    String cancelled = '0',
    int? pageNumber,
    int? pageLimit,
  }) async {
    if (!_connectivity.isOnline.value) {
      return _receiptsFromCache(
        cancelled: cancelled,
        filterFromDate: filterFromDate,
        filterToDate: filterToDate,
        searchText: searchText,
        filterPartyId: filterPartyId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    }

    try {
      final json = await _apiClient.postJson(
        ApiEndpoints.receipt,
        body: {
          'receipt_listing': '1',
          'filter_from_date': filterFromDate,
          'filter_to_date': filterToDate,
          'search_text': searchText,
          'filter_party_id': filterPartyId,
          'cancelled': cancelled,
          if (pageNumber != null) 'page_number': pageNumber.toString(),
          if (pageLimit != null) 'page_limit': pageLimit.toString(),
        },
      );

      final result = ReceiptListResponseModel.fromJson(json);
      if (result.isSuccess) return result;

      throw ApiRequestException(result.message);
    } on NetworkException {
      return _receiptsFromCache(
        cancelled: cancelled,
        filterFromDate: filterFromDate,
        filterToDate: filterToDate,
        searchText: searchText,
        filterPartyId: filterPartyId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    } on TimeoutApiException {
      return _receiptsFromCache(
        cancelled: cancelled,
        filterFromDate: filterFromDate,
        filterToDate: filterToDate,
        searchText: searchText,
        filterPartyId: filterPartyId,
        pageNumber: pageNumber,
        pageLimit: pageLimit,
      );
    }
  }

  /// [cancelled] picks which cached tab snapshot to read from —
  /// [DataSyncService] stores Active/Cancel separately (Receipts have no
  /// Draft tab), the same split the server's `cancelled` flag produces.
  ReceiptListResponseModel _receiptsFromCache({
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final cacheKey =
        cancelled == '1' ? CacheKeys.receiptCancel : CacheKeys.receiptActive;

    final all = _cache
        .getJsonList(cacheKey)
        .map(ReceiptListItem.fromJson)
        .toList();

    final partyList = _cache
        .getJsonList(CacheKeys.receiptParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    String? nameForId(List<IdName> options, String id) {
      for (final o in options) {
        if (o.id == id) return o.name;
      }
      return null;
    }

    final partyName =
        filterPartyId.isEmpty ? null : nameForId(partyList, filterPartyId);

    final filtered = all.where((r) {
      if (!matchesDateRange(r.receiptDate, filterFromDate, filterToDate)) {
        return false;
      }
      if (partyName != null &&
          !r.partyName.toLowerCase().contains(partyName.toLowerCase())) {
        return false;
      }
      return matchesSearch(searchText, [
        r.receiptNumber,
        r.partyName,
        r.agentName,
      ]);
    }).toList();

    return ReceiptListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      partyList: partyList,
    );
  }

  /// Creates a new Billwise Payment receipt against [againstBillNumber].
  /// [entries] becomes the three parallel `payment_mode_id` / `bank_id` /
  /// `amount` arrays exactly as captured in the Postman example.
  Future<ReceiptSaveResponseModel> saveReceipt({
    required String creator,
    required String receiptDate, // dd-MM-yyyy
    required String againstBillNumber,
    String deduction = '',
    String narration = '',
    required List<ReceiptPaymentEntry> entries,
  }) async {
    final body = <String, dynamic>{
      'receipt_update': '1',
      'creator': creator,
      'receipt_date': receiptDate,
      'against_bill_number': againstBillNumber,
      'deduction': deduction,
      'narration': narration,
      'payment_mode_id': entries.map((e) => e.paymentModeId).toList(),
      'bank_id': entries.map((e) => e.bankId).toList(),
      'amount': entries.map((e) => e.amount).toList(),
    };

    final json = await _apiClient.postJson(ApiEndpoints.receipt, body: body);

    final result = ReceiptSaveResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Deletes/cancels a receipt (soft-void — payment entries are reversed
  /// server-side). There is no "restore" — matches the Receipt list only
  /// ever showing active rows.
  Future<ReceiptDeleteResponseModel> deleteReceipt({
    required String receiptId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'delete_receipt_id': receiptId},
    );

    final result = ReceiptDeleteResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}