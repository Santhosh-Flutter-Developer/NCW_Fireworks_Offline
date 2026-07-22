import '../../../core/network/api_exception.dart';

/// Parses the `{"head": {...}}` envelope returned by
/// `retail_mobile_app/API/login.php`.
///
/// Known success shape:
/// ```json
/// {
///   "head": {
///     "code": 200,
///     "msg": "Login Successfully",
///     "user_id": "<opaque session/user identifier>",
///     "name": "NCW Fireworks Retail (1234567890)",
///     "bill_prefix": "AKB"
///   }
/// }
/// ```
///
/// The failure shape hasn't been confirmed against the live API yet, so
/// this parser is deliberately defensive: it only ever trusts [code] and
/// requires a non-empty [userId] before treating the call as a genuine
/// success, rather than assuming every 200 means "logged in".
class LoginResponseModel {
  final int code;
  final String message;
  final String? userId;
  final String? name;

  /// This business's short prefix for document numbers it generates on
  /// this device (e.g. `AKB` in `AKBQUT006/26-27`) — quotations are the
  /// first document type to need it, since `quotation_number` is now
  /// generated client-side instead of by the server. Empty when the
  /// server hasn't set one for this account.
  final String billPrefix;

  const LoginResponseModel({
    required this.code,
    required this.message,
    this.userId,
    this.name,
    this.billPrefix = '',
  });

  /// True only when the server both reports success AND gave us a usable
  /// user identifier — protects against a malformed "success" response
  /// silently letting someone into the app with no real session.
  bool get isSuccess =>
      code == 200 && userId != null && userId!.trim().isNotEmpty;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) {
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

    final rawUserId = head['user_id'];
    final rawName = head['name'];

    return LoginResponseModel(
      code: code,
      message: message,
      userId: (rawUserId is String && rawUserId.trim().isNotEmpty)
          ? rawUserId.trim()
          : null,
      name: (rawName is String && rawName.trim().isNotEmpty)
          ? rawName.trim()
          : null,
      billPrefix: head['bill_prefix']?.toString().trim() ?? '',
    );
  }
}