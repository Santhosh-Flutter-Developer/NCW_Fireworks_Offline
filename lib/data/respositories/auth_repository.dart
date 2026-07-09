import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/auth/login_response_model.dart';

/// Talks to `login.php`. Every method either returns a successful,
/// fully-validated [LoginResponseModel] or throws a typed [ApiException]
/// — callers never need to check for nulls or guess at error shapes.
class AuthRepository {
  AuthRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<LoginResponseModel> login({
    required String username,
    required String password,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.login,
      body: {
        'username': username,
        'password': password,
      },
    );

    final result = LoginResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    if (result.code == 200) {
      // Server claimed success but didn't give us anything we can build
      // a session from — don't let that silently pass as a login.
      throw const InvalidResponseException();
    }

    // Any non-200 head.code is treated as rejected credentials. If the
    // live API turns out to distinguish "wrong password" from "server
    // error" via a different code range, tighten this check accordingly.
    throw InvalidCredentialsException(result.message);
  }
}