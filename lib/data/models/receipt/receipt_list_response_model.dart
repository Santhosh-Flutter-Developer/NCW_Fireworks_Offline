import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One row from `receipt_list` in a `receipt_listing` response.
class ReceiptListItem {
  final String receiptId;
  final String receiptNumber;
  final String receiptDate; // yyyy-MM-dd, as stored server-side
  final String agentName;
  final String partyName;
  final double totalAmount;

  const ReceiptListItem({
    required this.receiptId,
    required this.receiptNumber,
    required this.receiptDate,
    required this.agentName,
    required this.partyName,
    required this.totalAmount,
  });

  factory ReceiptListItem.fromJson(Map<String, dynamic> json) {
    return ReceiptListItem(
      receiptId: json['receipt_id']?.toString() ?? '',
      receiptNumber: json['receipt_number']?.toString() ?? '',
      receiptDate: json['receipt_date']?.toString() ?? '',
      agentName: json['agent_name']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      totalAmount: readNum(json['total_amount']),
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `receipt_listing`
/// call.
///
/// Also carries `party_list` (same `{party_id, party_name}` shape as
/// `quotation_listing`) so the list screen's Party filter dropdown can be
/// populated the same way the Quotation screen's is.
class ReceiptListResponseModel {
  final int code;
  final String message;
  final List<ReceiptListItem> items;
  final List<IdName> partyList;

  /// Total rows matching the current filters, independent of pagination —
  /// derived from the fully-synced local cache (see
  /// `ReceiptRepository._cachedTotalCount`), not from this particular
  /// page's response. Null when there's no synced snapshot yet to count
  /// against, in which case the caller falls back to inferring "is there
  /// a next page" from whether this page came back full.
  final int? totalRecords;

  const ReceiptListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.partyList,
    this.totalRecords,
  });

  bool get isSuccess => code == 200;

  factory ReceiptListResponseModel.fromJson(Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final items = <ReceiptListItem>[];
    final rawList = head['receipt_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          items.add(ReceiptListItem.fromJson(Map<String, dynamic>.from(row)));
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

    return ReceiptListResponseModel(
      code: readCode(head['code']),
      message: readMsg(head['msg']),
      items: items,
      partyList: readIdNameList(head['party_list'], 'party_id', 'party_name'),
    );
  }
}
