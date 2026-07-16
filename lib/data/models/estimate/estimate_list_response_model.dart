import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One row from `estimate_list` in an `estimate_listing` response.
///
/// Note: the endpoint doesn't return a status/drafted flag per row, only
/// id/number/date/agent/party/qty/total — so the UI can't tell active vs
/// draft vs cancelled estimates apart from this list alone.
class EstimateListItem {
  final String estimateId;
  final String estimateNumber;
  final String estimateDate; // yyyy-MM-dd, as stored server-side
  final String agentNameMobileCity;
  final String partyNameMobileCity;
  final String totalQuantity;
  final double grandTotal;
  final String receiptId;

  const EstimateListItem({
    required this.estimateId,
    required this.estimateNumber,
    required this.estimateDate,
    required this.agentNameMobileCity,
    required this.partyNameMobileCity,
    required this.totalQuantity,
    required this.grandTotal,
    this.receiptId = '',
  });

  factory EstimateListItem.fromJson(Map<String, dynamic> json) {
    return EstimateListItem(
      estimateId: json['estimate_id']?.toString() ?? '',
      estimateNumber: json['estimate_number']?.toString() ?? '',
      estimateDate: json['estimate_date']?.toString() ?? '',
      agentNameMobileCity: json['agent_name_mobile_city']?.toString() ?? '',
      partyNameMobileCity: json['party_name_mobile_city']?.toString() ?? '',
      totalQuantity: json['total_quantity']?.toString() ?? '',
      grandTotal: readNum(json['grand_total']),
      receiptId: json["receipt_id"]?.toString() ?? '',
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for an `estimate_listing`
/// call.
class EstimateListResponseModel {
  final int code;
  final String message;
  final List<EstimateListItem> items;
  final List<IdName> agentList;
  final List<IdName> partyList;

  const EstimateListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.agentList,
    required this.partyList,
  });

  bool get isSuccess => code == 200;

  factory EstimateListResponseModel.fromJson(Map<String, dynamic> json) {
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

    final items = <EstimateListItem>[];
    final rawList = head['estimate_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          items.add(EstimateListItem.fromJson(Map<String, dynamic>.from(row)));
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

    return EstimateListResponseModel(
      code: code,
      message: message,
      items: items,
      agentList: readIdNameList(head['agent_list'], 'agent_id', 'agent_name'),
      partyList: readIdNameList(head['party_list'], 'party_id', 'party_name'),
    );
  }
}
