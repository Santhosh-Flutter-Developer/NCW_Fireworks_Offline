import '../../../core/network/api_exception.dart';

/// Parses the `{"head": {...}}` envelope returned by `estimate.php` for an
/// `estimate_update` (create or edit) call.
///
/// Success shape:
/// ```json
/// { "head": { "code": 200, "msg": "Estimate Successfully Created" } }
/// ```
/// Failure shape (validation rejection):
/// ```json
/// { "head": { "code": 400, "msg": "Select the products" } }
/// ```
class EstimateSaveResponseModel {
  final int code;
  final String message;

  const EstimateSaveResponseModel({required this.code, required this.message});

  bool get isSuccess => code == 200;

  factory EstimateSaveResponseModel.fromJson(Map<String, dynamic> json) {
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

    return EstimateSaveResponseModel(code: code, message: message);
  }
}
