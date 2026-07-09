import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin wrapper around [http.Client] that centralizes request timeouts,
/// standard headers, and translation of low-level errors (sockets,
/// timeouts, malformed JSON, non-2xx status codes) into the typed
/// [ApiException] hierarchy — so repositories and controllers never have
/// to deal with raw `SocketException` / `FormatException` themselves.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> postJson(
    Uri url, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    if (url.scheme != 'https' && !kDebugMode) {
      // Guard against accidentally shipping a build that talks to the
      // API over plain HTTP (credentials would go over the wire in
      // clear text). Allowed only in debug builds against local servers.
      throw const NetworkException(
        'Insecure connection blocked. The server must be accessed over HTTPS.',
      );
    }

    http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              ...?headers,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const TimeoutApiException();
    } on SocketException {
      throw const NetworkException();
    } on HandshakeException {
      throw const NetworkException(
        'A secure connection to the server could not be established.',
      );
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      // Malformed URL, etc. — programmer error, but don't crash the UI.
      throw const InvalidResponseException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerException(response.statusCode);
    }

    final rawBody = response.body.trim();
    if (rawBody.isEmpty) {
      throw const InvalidResponseException('Empty response from server.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } on FormatException {
      throw const InvalidResponseException();
    }

    if (decoded is! Map<String, dynamic>) {
      throw const InvalidResponseException();
    }

    return decoded;
  }
}