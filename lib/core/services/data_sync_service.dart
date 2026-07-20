import 'dart:convert';
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

  /// Rows per page while paging through each list end-to-end. Set high
  /// on purpose: for a catalog this app's size, one or two requests
  /// should cover an entire list. A small page size is what turns a few
  /// thousand rows into dozens of slow, chatty round trips.
  static const _pageLimit = 2000;

  /// Hard cap on pages per section/tab — a safety net against an
  /// endpoint that never returns a short page (server-side pagination
  /// bug, ignored `page_number`, etc). With a 2,000-row page size this
  /// still allows up to 20,000 rows per tab before giving up, while
  /// keeping a real ceiling on requests if something server-side never
  /// terminates the page sequence.
  static const _maxPages = 10;

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
    } finally {
      isSyncing.value = false;
      statusMessage.value = '';
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

  /// Updates [statusMessage] with exactly what's being synced right now
  /// (e.g. "Syncing quotations — Draft, page 2"), for the top status
  /// strip in [AppScaffold] to display while [isSyncing] is true.
  void _announce(String message) {
    statusMessage.value = message;
  }

  /// Whether [page] looks like the *same* page as [previous] — same
  /// number of rows and identical first/last row content. A server that
  /// ignores `page_number` (or has some other pagination bug) tends to
  /// keep returning a full page of identical rows forever; this catches
  /// that after a single repeat instead of hammering it for
  /// [_maxPages] requests every single sync.
  bool _isRepeatedPage(
    List<Map<String, dynamic>>? previous,
    List<Map<String, dynamic>> page,
  ) {
    if (previous == null) return false;
    if (previous.length != page.length) return false;
    if (page.isEmpty) return false;
    return jsonEncode(previous.first) == jsonEncode(page.first) &&
        jsonEncode(previous.last) == jsonEncode(page.last);
  }

  Future<void> _syncParties() async {
    final items = <Map<String, dynamic>>[];
    List<Map<String, dynamic>>? previousPage;
    var page = 1;
    while (page <= _maxPages) {
      _announce('Syncing parties — page $page');
      final result = await _partyRepository.listParties(
        pageNumber: page,
        pageLimit: _pageLimit,
      );
      final pageItems = result.items
          .map((p) => {
                'party_id': p.partyId,
                'party_name': p.partyName,
                'state': p.state,
              })
          .toList();
      if (pageItems.isEmpty || _isRepeatedPage(previousPage, pageItems)) break;
      items.addAll(pageItems);
      if (pageItems.length < _pageLimit) break;
      previousPage = pageItems;
      page++;
    }
    await _cache.putJsonList(CacheKeys.party, items);
  }

  Future<void> _syncPriceList() async {
    final rows = <Map<String, dynamic>>[];
    final pricelists = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    List<Map<String, dynamic>>? previousPage;
    var page = 1;
    while (page <= _maxPages) {
      _announce('Syncing price list — page $page');
      final result = await _productPriceRepository.fetchPriceList(
        pageNumber: page,
        pageLimit: _pageLimit,
      );
      final pageRows = result.rows
          .map((r) => {
                'sno': r.sno,
                'pricelist_name': r.pricelistName,
                'product_name': r.productName,
                'price': r.price,
                'price_unit_name': r.unit,
                'discount': r.discountEnabled ? 'ON' : 'OFF',
              })
          .toList();

      for (final p in result.pricelists) {
        pricelists[p.id] = {'pricelist_id': p.id, 'pricelist_name': p.name};
      }
      for (final p in result.products) {
        products[p.id] = {'product_id': p.id, 'product_name': p.name};
      }

      if (pageRows.isEmpty || _isRepeatedPage(previousPage, pageRows)) break;
      rows.addAll(pageRows);
      if (pageRows.length < _pageLimit) break;
      previousPage = pageRows;
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
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      final items = <Map<String, dynamic>>[];
      List<Map<String, dynamic>>? previousPage;
      var page = 1;
      while (page <= _maxPages) {
        _announce('Syncing quotations — $tabLabel, page $page');
        final result = await _quotationRepository.listQuotations(
          pageNumber: page,
          pageLimit: _pageLimit,
          drafted: drafted,
          cancelled: cancelled,
        );
        final pageItems = result.items
            .map((q) => {
                  'quotation_id': q.quotationId,
                  'quotation_number': q.quotationNumber,
                  'quotation_date': q.quotationDate,
                  'party_name_mobile_city': q.partyNameMobileCity,
                  'total_quantity': q.totalQuantity,
                  'grand_total': q.grandTotal,
                  'estimate_id': q.estimateId,
                })
            .toList();
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (pageItems.isEmpty || _isRepeatedPage(previousPage, pageItems)) {
          break;
        }
        items.addAll(pageItems);
        if (pageItems.length < _pageLimit) break;
        previousPage = pageItems;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Quotation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.quotationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.quotationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.quotationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.quotationParties, parties.values.toList());
  }

  Future<void> _syncEstimations() async {
    final agents = <String, Map<String, dynamic>>{};
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      final items = <Map<String, dynamic>>[];
      List<Map<String, dynamic>>? previousPage;
      var page = 1;
      while (page <= _maxPages) {
        _announce('Syncing estimations — $tabLabel, page $page');
        final result = await _estimateRepository.listEstimates(
          pageNumber: page,
          pageLimit: _pageLimit,
          drafted: drafted,
          cancelled: cancelled,
        );
        final pageItems = result.items
            .map((e) => {
                  'estimate_id': e.estimateId,
                  'estimate_number': e.estimateNumber,
                  'estimate_date': e.estimateDate,
                  'agent_name_mobile_city': e.agentNameMobileCity,
                  'party_name_mobile_city': e.partyNameMobileCity,
                  'total_quantity': e.totalQuantity,
                  'grand_total': e.grandTotal,
                  'receipt_id': e.receiptId,
                })
            .toList();
        for (final a in result.agentList) {
          agents[a.id] = {'id': a.id, 'name': a.name};
        }
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (pageItems.isEmpty || _isRepeatedPage(previousPage, pageItems)) {
          break;
        }
        items.addAll(pageItems);
        if (pageItems.length < _pageLimit) break;
        previousPage = pageItems;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Estimation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.estimationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.estimationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.estimationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.estimationAgents, agents.values.toList());
    await _cache.putJsonList(
        CacheKeys.estimationParties, parties.values.toList());
  }

  Future<void> _syncReceipts() async {
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String cancelled,
    }) async {
      final items = <Map<String, dynamic>>[];
      List<Map<String, dynamic>>? previousPage;
      var page = 1;
      while (page <= _maxPages) {
        _announce('Syncing receipts — $tabLabel, page $page');
        final result = await _receiptRepository.listReceipts(
          pageNumber: page,
          pageLimit: _pageLimit,
          cancelled: cancelled,
        );
        final pageItems = result.items
            .map((r) => {
                  'receipt_id': r.receiptId,
                  'receipt_number': r.receiptNumber,
                  'receipt_date': r.receiptDate,
                  'agent_name': r.agentName,
                  'party_name': r.partyName,
                  'total_amount': r.totalAmount,
                })
            .toList();
        for (final p in result.partyList) {
          parties[p.id] = {'id': p.id, 'name': p.name};
        }
        if (pageItems.isEmpty || _isRepeatedPage(previousPage, pageItems)) {
          break;
        }
        items.addAll(pageItems);
        if (pageItems.length < _pageLimit) break;
        previousPage = pageItems;
        page++;
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Receipts only have Active/Cancel — no draft state.
    await syncTab(CacheKeys.receiptActive, 'Active', cancelled: '0');
    await syncTab(CacheKeys.receiptCancel, 'Cancelled', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.receiptParties, parties.values.toList());
  }
}
