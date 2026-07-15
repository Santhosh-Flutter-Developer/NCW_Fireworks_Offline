import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One row from `quotation_list` in a `quotation_listing` response.
///
/// Note: the endpoint doesn't return a status/drafted flag per row, only
/// id/number/date/party/qty/total — the list screen instead asks for one
/// status at a time via the `drafted`/`cancelled` request flags.
class QuotationListItem {
  final String quotationId;
  final String quotationNumber;
  final String quotationDate; // yyyy-MM-dd, as stored server-side
  final String partyNameMobileCity;
  final String totalQuantity;
  final double grandTotal;

  /// The linked estimate's id once this quotation has been converted —
  /// empty for quotations that haven't been converted yet. Drives whether
  /// the Convert/Edit/Delete actions show on the list row.
  final String estimateId;

  const QuotationListItem({
    required this.quotationId,
    required this.quotationNumber,
    required this.quotationDate,
    required this.partyNameMobileCity,
    required this.totalQuantity,
    required this.grandTotal,
    this.estimateId = '',
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
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `quotation_listing`
/// call.
class QuotationListResponseModel {
  final int code;
  final String message;
  final List<QuotationListItem> items;
  final List<IdName> partyList;

  const QuotationListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.partyList,
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