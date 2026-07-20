import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../../data/respositories/estimate_repository.dart';
import '../../data/respositories/party_repository.dart';
import '../../data/respositories/product_price_repository.dart';
import '../../data/respositories/quotation_repository.dart';
import '../../data/respositories/receipt_repository.dart';
import 'cache_keys.dart';
import 'local_cache_service.dart';

/// Pulls the full Party / Price Upload / Quotation / Estimation / Receipt
/// lists down from the API and caches them locally, so the rest of the
/// app has something to work from once the connection drops.
///
/// Run once, right after a *successful online* login (see
/// `LoginController`). Every list endpoint here is server-paginated, so
/// each section pages through with a large page size until a
/// short-of-a-full-page response tells us we've hit the end.
///
/// A single section failing (timeout, server hiccup mid-sync, etc.)
/// never throws out of [syncAll] — the user is already validly logged in
/// by the time this runs, so the worst case is "some lists are stale",
/// not "login is broken". [lastError] surfaces the most recent failure
/// for anyone who wants to show a subtle warning.
class DataSyncService extends GetxService {
  DataSyncService({
    PartyRepository? partyRepository,
    ProductPriceRepository? productPriceRepository,
    QuotationRepository? quotationRepository,
    EstimateRepository? estimateRepository,
    ReceiptRepository? receiptRepository,
    LocalCacheService? cache,
  })  : _partyRepository = partyRepository ?? PartyRepository(),
        _productPriceRepository =
            productPriceRepository ?? ProductPriceRepository(),
        _quotationRepository = quotationRepository ?? QuotationRepository(),
        _estimateRepository = estimateRepository ?? EstimateRepository(),
        _receiptRepository = receiptRepository ?? ReceiptRepository(),
        _cache = cache ?? Get.find<LocalCacheService>();

  final PartyRepository _partyRepository;
  final ProductPriceRepository _productPriceRepository;
  final QuotationRepository _quotationRepository;
  final EstimateRepository _estimateRepository;
  final ReceiptRepository _receiptRepository;
  final LocalCacheService _cache;

  /// Rows per page while paging through each list end-to-end. Large
  /// enough to keep the request count small, small enough to stay well
  /// under typical PHP/MySQL `LIMIT` and payload-size comfort zones.
  static const _pageLimit = 200;

  /// Hard cap on pages per section — a safety net against an endpoint
  /// that never returns a short page (e.g. `total % pageLimit == 0`
  /// forever due to a server bug), not an expected ceiling.
  static const _maxPages = 100;

  final isSyncing = false.obs;
  final statusMessage = ''.obs;
  final RxnString lastError = RxnString();

  Future<void> syncAll() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = null;
    try {
      await _runStep('Syncing parties…', _syncParties);
      await _runStep('Syncing price list…', _syncPriceList);
      await _runStep('Syncing quotations…', _syncQuotations);
      await _runStep('Syncing estimations…', _syncEstimations);
      await _runStep('Syncing receipts…', _syncReceipts);
      await _cache.putString(
        CacheKeys.lastSyncedAt,
        DateTime.now().toIso8601String(),
      );
      statusMessage.value = 'All caught up';
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _runStep(String label, Future<void> Function() step) async {
    statusMessage.value = label;
    try {
      await step();
    } catch (e, st) {
      lastError.value = e.toString();
      developer.log(
        'Offline sync step failed: $label',
        error: e,
        stackTrace: st,
        name: 'DataSyncService',
      );
    }
  }

  Future<void> _syncParties() async {
    final items = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= _maxPages) {
      final result = await _partyRepository.listParties(
        pageNumber: page,
        pageLimit: _pageLimit,
      );
      items.addAll(result.items.map((p) => {
            'party_id': p.partyId,
            'party_name': p.partyName,
            'state': p.state,
          }));
      if (result.items.length < _pageLimit) break;
      page++;
    }
    await _cache.putJsonList(CacheKeys.party, items);
  }

  Future<void> _syncPriceList() async {
    final rows = <Map<String, dynamic>>[];
    final pricelists = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    var page = 1;
    while (page <= _maxPages) {
      final result = await _productPriceRepository.fetchPriceList(
        pageNumber: page,
        pageLimit: _pageLimit,
      );
      rows.addAll(result.rows.map((r) => {
            'sno': r.sno,
            'pricelist_name': r.pricelistName,
            'product_name': r.productName,
            'price': r.price,
            'price_unit_name': r.unit,
            'discount': r.discountEnabled ? 'ON' : 'OFF',
          }));
      for (final p in result.pricelists) {
        pricelists[p.id] = {'pricelist_id': p.id, 'pricelist_name': p.name};
      }
      for (final p in result.products) {
        products[p.id] = {'product_id': p.id, 'product_name': p.name};
      }
      if (result.rows.length < _pageLimit) break;
      page++;
    }
    await _cache.putJsonList(CacheKeys.priceRows, rows);
    await _cache.putJsonList(
        CacheKeys.priceLists, pricelists.values.toList());
    await _cache.putJsonList(CacheKeys.priceProducts, products.values.toList());
  }

  Future<void> _syncQuotations() async {
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey, {
      required String drafted,
      required String cancelled,
    }) async {
      final items = <Map<String, dynamic>>[];
      var page = 1;
      while (page <= _maxPages) {
        final result = await _quotationRepository.listQuotations(
          pageNumber: page,
          pageLimit: _pageLimit,
          drafted: drafted,
          cancelled: cancelled,
        );
        items.addAll(result.items.map((q) => {
              'quotation_id': q.quotationId,
              'quotation_number': q.quotationNumber,
              'quotation_date': q.quotationDate,
              'party_name_mobile_city': q.partyNameMobileCity,
              'total_quantity': q.totalQuantity,
              'grand_total': q.grandTotal,
              'estimate_id': q.estimateId,
            }));
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (result.items.length < _pageLimit) break;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Quotation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.quotationActive, drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.quotationDraft, drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.quotationCancel, drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.quotationParties, parties.values.toList());
  }

  Future<void> _syncEstimations() async {
    final agents = <String, Map<String, dynamic>>{};
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey, {
      required String drafted,
      required String cancelled,
    }) async {
      final items = <Map<String, dynamic>>[];
      var page = 1;
      while (page <= _maxPages) {
        final result = await _estimateRepository.listEstimates(
          pageNumber: page,
          pageLimit: _pageLimit,
          drafted: drafted,
          cancelled: cancelled,
        );
        items.addAll(result.items.map((e) => {
              'estimate_id': e.estimateId,
              'estimate_number': e.estimateNumber,
              'estimate_date': e.estimateDate,
              'agent_name_mobile_city': e.agentNameMobileCity,
              'party_name_mobile_city': e.partyNameMobileCity,
              'total_quantity': e.totalQuantity,
              'grand_total': e.grandTotal,
              'receipt_id': e.receiptId,
            }));
        for (final a in result.agentList) {
          agents[a.id] = {'id': a.id, 'name': a.name};
        }
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (result.items.length < _pageLimit) break;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Estimation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.estimationActive, drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.estimationDraft, drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.estimationCancel, drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.estimationAgents, agents.values.toList());
    await _cache.putJsonList(
        CacheKeys.estimationParties, parties.values.toList());
  }

  Future<void> _syncReceipts() async {
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(String cacheKey, {required String cancelled}) async {
      final items = <Map<String, dynamic>>[];
      var page = 1;
      while (page <= _maxPages) {
        final result = await _receiptRepository.listReceipts(
          pageNumber: page,
          pageLimit: _pageLimit,
          cancelled: cancelled,
        );
        items.addAll(result.items.map((r) => {
              'receipt_id': r.receiptId,
              'receipt_number': r.receiptNumber,
              'receipt_date': r.receiptDate,
              'agent_name': r.agentName,
              'party_name': r.partyName,
              'total_amount': r.totalAmount,
            }));
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (result.items.length < _pageLimit) break;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Receipts only have Active/Cancel — no draft state.
    await syncTab(CacheKeys.receiptActive, cancelled: '0');
    await syncTab(CacheKeys.receiptCancel, cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.receiptParties, parties.values.toList());
  }
}
