import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Automatic crypto-payment order bridge. Order creation and blockchain
/// verification remain backend-owned; the client never grants entitlements.
class AutomaticPaymentService {
  static const String endpoint = String.fromEnvironment(
    'CDH_DRIVE_BACKEND_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzMvodYlFaFeFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec',
  );

  static Uri _uri() {
    if (endpoint.trim().isEmpty) {
      throw StateError('Automatic payment backend is not configured.');
    }
    return Uri.parse(endpoint);
  }

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Authentication required.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Could not obtain Firebase authentication token.');
    final payload = <String, dynamic>{...body, 'idToken': token};
    final response = await http.post(_uri(), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
      throw StateError((decoded['error'] ?? 'Automatic payment backend failed (${response.statusCode}).').toString());
    }
    return decoded;
  }

  /// TEMPORARY backend authentication connectivity test.
  /// This verifies the currently signed-in Firebase user against the
  /// deployed Apps Script backend. Remove after the test is confirmed.
  static Future<Map<String, dynamic>> testAuthenticatedIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Authentication required.');
    }

    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Could not obtain Firebase authentication token.');
    }

    final requestBody = jsonEncode({
      'action': 'auth_test',
      'idToken': token,
    });

    final ioHttpClient = HttpClient();
    http.Response response;

    try {
      response = await _sendAuthTestPost_(
        ioHttpClient,
        _uri(),
        requestBody,
      );

      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw StateError(
            'Backend redirected the authentication request without a Location header.',
          );
        }

        // Apps Script ContentService returns the actual response from a
        // one-time script.googleusercontent.com URL. The original POST has
        // already executed; the redirect target must therefore be fetched
        // with GET, not by replaying the POST body.
        final redirectUri = Uri.parse(location);
        response = await _sendAuthTestRedirectGet_(
          ioHttpClient,
          redirectUri,
        );
      }
    } finally {
      ioHttpClient.close(force: true);
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
      throw StateError(
        (decoded['message'] ?? decoded['error'] ??
                'Backend authentication test failed (${response.statusCode}).')
            .toString(),
      );
    }

    return decoded;
  }

  static Future<http.Response> _sendAuthTestPost_(
    HttpClient client,
    Uri uri,
    String requestBody,
  ) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set('Content-Type', 'application/json');
    request.write(requestBody);

    final rawResponse = await request.close();
    final body = await rawResponse.transform(utf8.decoder).join();
    final headers = <String, String>{};

    rawResponse.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return http.Response(
      body,
      rawResponse.statusCode,
      headers: headers,
      request: http.Request('POST', uri),
    );
  }

  static Future<http.Response> _sendAuthTestRedirectGet_(
    HttpClient client,
    Uri uri,
  ) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;

    final rawResponse = await request.close();
    final body = await rawResponse.transform(utf8.decoder).join();
    final headers = <String, String>{};

    rawResponse.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return http.Response(
      body,
      rawResponse.statusCode,
      headers: headers,
      request: http.Request('GET', uri),
    );
  }

  static Future<Map<String, dynamic>> createOrder({
    required String product,
    required String planId,
    required String network,
  }) async {
    return _post({'action': 'createOrder', 'product': product, 'planId': planId, 'network': network});
  }

  static Future<Map<String, dynamic>> submitTransaction({
    required String orderId,
    required String transactionHash,
  }) async {
    return _post({'action': 'submitTxHash', 'orderId': orderId, 'transactionHash': transactionHash.trim()});
  }

  static Future<Map<String, dynamic>> getOrder(String orderId) async {
    return _post({'action': 'getOrder', 'orderId': orderId});
  }
}
