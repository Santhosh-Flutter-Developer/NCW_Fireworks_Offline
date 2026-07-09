/// Lightweight, dependency-free input validation shared across forms.
/// These are intentionally permissive on the password rules — the
/// backend, not this client, owns the real credential policy — and
/// exist mainly to reject empty/garbage input before spending a
/// network round trip on it.
class Validators {
  Validators._();

  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your username';
    if (v.length < 3) return 'Username must be at least 3 characters';
    if (v.length > 60) return 'Username is too long';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter your password';
    if (v.length < 4) return 'Password must be at least 4 characters';
    if (v.length > 128) return 'Password is too long';
    return null;
  }
}