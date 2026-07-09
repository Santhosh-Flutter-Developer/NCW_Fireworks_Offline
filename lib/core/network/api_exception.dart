sealed class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Device has no internet connection, DNS resolution failed, or the
/// socket connection was refused/reset.
class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'No internet connection. Please check your network and try again.',
  ]);
}

/// The request did not complete within the allowed time.
class TimeoutApiException extends ApiException {
  const TimeoutApiException([
    super.message = 'The request timed out. Please try again.',
  ]);
}

/// Server responded with a non-2xx HTTP status code.
class ServerException extends ApiException {
  final int? statusCode;
  const ServerException(this.statusCode, [
    super.message = 'Something went wrong on the server. Please try again later.',
  ]);
}

/// Server responded with HTTP 200 but the payload wasn't the JSON shape
/// we expect (missing/renamed fields, HTML error page, empty body, etc).
class InvalidResponseException extends ApiException {
  const InvalidResponseException([
    super.message = 'Unexpected response from server. Please try again later.',
  ]);
}

/// Server explicitly rejected the supplied credentials.
class InvalidCredentialsException extends ApiException {
  const InvalidCredentialsException([
    super.message = 'Invalid username or password.',
  ]);
}