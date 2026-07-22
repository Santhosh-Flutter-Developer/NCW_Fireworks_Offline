/// The locally persisted "logged in" session. Deliberately holds only
/// what the login API actually gives us (`user_id`, `name`, `bill_prefix`)
/// plus a timestamp — no password or other sensitive material is ever
/// stored.
class AuthSessionModel {
  final String userId;
  final String name;
  final DateTime loggedInAt;

  /// This business's short document-number prefix (e.g. `AKB`) — used to
  /// build `quotation_number` client-side (`AKBQUT006/26-27`) now that
  /// the server no longer generates it. Empty for a session restored
  /// from before this field existed, or if the server hasn't set one.
  final String billPrefix;

  const AuthSessionModel({
    required this.userId,
    required this.name,
    required this.loggedInAt,
    this.billPrefix = '',
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
        'logged_in_at': loggedInAt.toIso8601String(),
        'bill_prefix': billPrefix,
      };

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final name = json['name'];
    if (userId is! String || userId.isEmpty || name is! String) {
      throw const FormatException('Malformed session payload');
    }
    return AuthSessionModel(
      userId: userId,
      name: name,
      loggedInAt:
          DateTime.tryParse(json['logged_in_at'] as String? ?? '') ??
              DateTime.now(),
      // Missing entirely for a session saved before this field was
      // added — defaults to empty rather than failing to restore.
      billPrefix: json['bill_prefix']?.toString() ?? '',
    );
  }

  static final _nameWithPhonePattern = RegExp(r'^(.*?)\s*\(([^)]*)\)\s*$');

  /// The API's `name` field is often formatted as `"Business (phone)"`.
  /// This splits it for nicer display; falls back to the raw string for
  /// any other shape.
  String get displayName {
    final match = _nameWithPhonePattern.firstMatch(name);
    final label = match?.group(1)?.trim();
    return (label != null && label.isNotEmpty) ? label : name;
  }

  String? get displayPhone => _nameWithPhonePattern.firstMatch(name)?.group(2)?.trim();
}