import '../../../core/network/api_exception.dart';
import 'id_name.dart';
import 'quotation_init_response_model.dart';

/// One row from `quotation_list` in a `quotation_listing` response — or,
/// when [isPending] is true, one row built from the on-device
/// pending-sync queue ([CacheKeys.quotationPending]) instead.
///
/// `quotation_listing` actually returns every field below per row —
/// party/pricelist ids, the full product line-up, both sections' add/
/// discount values, and the draft flag — not just the id/number/date/
/// party/qty/total summary this used to parse. [hasFullDetails] is only
/// false for a row cached by an older build of this app that stored just
/// the summary fields; those still need a `show_quotation_id` fetch
/// before they can be edited safely (see
/// `QuotationController.startEdit`). A pending row (built via
/// [fromPendingRow]) always has full details — it was built on this
/// device, nothing to fetch.
class QuotationListItem {
  final String quotationId;
  final String quotationNumber;
  final String quotationDate; // dd-MM-yyyy, as `quotation_listing` sends it
  final String partyNameMobileCity;
  final String totalQuantity;
  final double grandTotal;

  /// The linked estimate's id once this quotation has been converted —
  /// empty for quotations that haven't been converted yet. Drives whether
  /// the Convert/Edit/Delete actions show on the list row.
  final String estimateId;

  /// True for a row sourced from the pending-sync queue rather than the
  /// synced cache — i.e. an add/edit made on this device that hasn't
  /// been sent to the server yet.
  final bool isPending;

  /// For a pending row, the queue entry's own id — used to find/replace
  /// this exact entry later (re-editing before sync, or removing it).
  /// Empty for a synced row.
  final String localId;

  final String partyId;
  final String pricelistId;
  final String pricelistName;
  final String agentId;
  final List<QuotationDetailProductRow> products;
  final String section1AddValue;
  final String section1Discount;
  final String section2AddValue;
  final String section2Discount;
  final bool isDraft;

  /// Whether every field above is actually known for this row — see the
  /// class doc for when this is false.
  final bool hasFullDetails;

  const QuotationListItem({
    required this.quotationId,
    required this.quotationNumber,
    required this.quotationDate,
    required this.partyNameMobileCity,
    required this.totalQuantity,
    required this.grandTotal,
    this.estimateId = '',
    this.isPending = false,
    this.localId = '',
    this.partyId = '',
    this.pricelistId = '',
    this.pricelistName = '',
    this.agentId = '',
    this.products = const [],
    this.section1AddValue = '',
    this.section1Discount = '',
    this.section2AddValue = '',
    this.section2Discount = '',
    this.isDraft = false,
    this.hasFullDetails = false,
  });

  factory QuotationListItem.fromJson(Map<String, dynamic> json) {
    return QuotationListItem(
      quotationId: json['quotation_id']?.toString() ?? '',
      quotationNumber: json['quotation_number']?.toString() ?? '',
      quotationDate: json['quotation_date']?.toString() ?? '',
      partyNameMobileCity: json['party_name_mobile_city']?.toString() ?? '',
      totalQuantity: json['total_quantity']?.toString() ?? '',
      grandTotal: readNum(json['grand_total']),
      estimateId: json['estimate_id']?.toString() ?? '',
      partyId: json['party_id']?.toString() ?? '',
      pricelistId: json['pricelist_id']?.toString() ?? '',
      pricelistName: json['pricelist_name']?.toString() ?? '',
      agentId: json['agent_id']?.toString() ?? '',
      products: _readProductRows(json),
      section1AddValue: json['section1_add_value']?.toString() ?? '',
      section1Discount: json['section1_discount']?.toString() ?? '',
      section2AddValue: json['section2_add_value']?.toString() ?? '',
      section2Discount: json['section2_discount']?.toString() ?? '',
      isDraft: json['drafted']?.toString() == '1',
      hasFullDetails: json['_full'] == true,
    );
  }

  /// Builds a row from one entry of the pending-sync queue (the same
  /// shape [QuotationRepository.queueQuotationForSync] writes).
  /// [quotationId] here is the row's `edit_id` — empty for a brand-new
  /// quotation not yet on the server, or the real server id when this is
  /// a queued edit of an already-synced quotation.
  factory QuotationListItem.fromPendingRow(Map<String, dynamic> row) {
    final rawProducts = row['product_data'];
    final products = <QuotationDetailProductRow>[
      if (rawProducts is List)
        for (final p in rawProducts)
          if (p is Map)
            QuotationDetailProductRow(
              productId: p['product_id']?.toString() ?? '',
              productName: p['product_name']?.toString() ?? '',
              quantity: p['product_quantity']?.toString() ?? '',
              unitId: p['unit_id']?.toString() ?? '',
              unitName: p['unit_name']?.toString() ?? '',
              rate: p['product_rate']?.toString() ?? '',
              productDiscount: p['product_discount']?.toString() ?? '',
              amount: '',
            ),
    ];

    return QuotationListItem(
      quotationId: row['edit_id']?.toString() ?? '',
      quotationNumber: '', // No bill number until the server confirms it.
      quotationDate: row['quotation_date']?.toString() ?? '',
      partyNameMobileCity: row['party_name']?.toString() ?? '',
      totalQuantity: products
          .fold<int>(0, (sum, p) => sum + (int.tryParse(p.quantity) ?? 0))
          .toString(),
      grandTotal: 0, // Recomputed by the form from its own line items.
      isPending: true,
      localId: row['local_id']?.toString() ?? '',
      partyId: row['party_id']?.toString() ?? '',
      pricelistId: row['pricelist_id']?.toString() ?? '',
      pricelistName: row['pricelist_name']?.toString() ?? '',
      agentId: row['agent_id']?.toString() ?? '',
      products: products,
      section1AddValue: row['section1_add_value']?.toString() ?? '',
      section1Discount: row['section1_discount']?.toString() ?? '',
      section2AddValue: row['section2_add_value']?.toString() ?? '',
      section2Discount: row['section2_discount']?.toString() ?? '',
      isDraft: row['drafted']?.toString() == '1',
      hasFullDetails: true,
    );
  }

  static List<QuotationDetailProductRow> _readProductRows(
      Map<String, dynamic> json) {
    final productIds = readStringList(json['product_id']);
    final productNames = readStringList(json['product_name']);
    final productQty = readStringList(json['product_quantity']);
    final unitIds = readStringList(json['unit_id']);
    final unitNames = readStringList(json['unit_name']);
    final rates = readStringList(json['product_rate']);
    final discountFlags = readStringList(json['product_discount']);
    final amounts = readStringList(json['product_amount']);

    String at(List<String> l, int i) => i < l.length ? l[i] : '';

    return [
      for (var i = 0; i < productIds.length; i++)
        if (productIds[i].isNotEmpty)
          QuotationDetailProductRow(
            productId: productIds[i],
            productName: at(productNames, i),
            quantity: at(productQty, i),
            unitId: at(unitIds, i),
            unitName: at(unitNames, i),
            rate: at(rates, i),
            productDiscount: at(discountFlags, i),
            amount: at(amounts, i),
          ),
    ];
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `quotation_listing`
/// call.
class QuotationListResponseModel {
  final int code;
  final String message;
  final List<QuotationListItem> items;
  final List<IdName> partyList;

  /// Total rows matching the current filters, independent of pagination —
  /// derived from the fully-synced local cache (see
  /// `QuotationRepository._cachedTotalCount`), not from this particular
  /// page's response. Null when there's no synced snapshot yet to count
  /// against, in which case the caller falls back to inferring "is there
  /// a next page" from whether this page came back full.
  final int? totalRecords;

  const QuotationListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.partyList,
    this.totalRecords,
  });

  bool get isSuccess => code == 200;

  factory QuotationListResponseModel.fromJson(Map<String, dynamic> json) {
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

    final items = <QuotationListItem>[];
    final rawList = head['quotation_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          items.add(
              QuotationListItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    List<IdName> readIdNameList(dynamic raw, String idKey, String nameKey) {
      final out = <IdName>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) {
            final m = Map<String, dynamic>.from(row);
            out.add(IdName(
              id: m[idKey]?.toString() ?? '',
              name: m[nameKey]?.toString() ?? '',
            ));
          }
        }
      }
      return out;
    }

    return QuotationListResponseModel(
      code: code,
      message: message,
      items: items,
      partyList:
          readIdNameList(head['party_list'], 'party_id', 'party_name'),
    );
  }
}