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
    if (user == null) {
      throw StateError('Authentication required.');
    }

    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Could not obtain Firebase authentication token.');
    }

    final payload = <String, dynamic>{
      ...body,
      'idToken': token,
    };

    final requestBody = jsonEncode(payload);
    final ioHttpClient = HttpClient();
    final cookies = <String, String>{};
    http.Response response;

    try {
      response = await _sendPostNoRedirect_(
        ioHttpClient,
        _uri(),
        requestBody,
        cookies,
      );

      var redirectCount = 0;
      while (_isRedirectStatus_(response.statusCode)) {
        redirectCount++;
        if (redirectCount > 8) {
          throw StateError(
            'Automatic payment backend redirected too many times.',
          );
        }

        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw StateError(
            'Automatic payment backend redirected without a Location header.',
          );
        }

        final redirectUri = response.request?.url.resolve(location) ??
            Uri.parse(location);

        response = await _sendRedirectGet_(
          ioHttpClient,
          redirectUri,
          cookies,
        );
      }
    } finally {
      ioHttpClient.close(force: true);
    }

    final decoded = _decodeCdhResponse_(response.body);

    final backendSucceeded =
        decoded['ok'] == true ||
        decoded['success'] == true;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !backendSucceeded) {
      final contentType = response.headers['content-type'] ?? 'unknown';
      final bodyPreview = response.body.trim();
      final message =
          decoded['message'] ??
          decoded['error'] ??
          'Automatic payment backend failed (${response.statusCode}).\n'
          'Response content-type: $contentType\n'
          'Response body: ${bodyPreview.isEmpty ? '(empty)' : bodyPreview}';
      throw StateError(message.toString());
    }

    return decoded;
  }

  /// Decodes both normal JSON responses and the CDH marker response
  /// returned by Apps Script HtmlService.
  static Map<String, dynamic> _decodeCdhResponse_(
    String responseBody,
  ) {
    final body = responseBody.trim();

    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    // First try normal JSON.
    try {
      final raw = jsonDecode(body);

      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // Continue with the CDH marker response.
    }

    const beginMarker = 'CDH_JSON_BEGIN';
    const endMarker = 'CDH_JSON_END';

    final beginIndex = body.indexOf(beginMarker);

    final endIndex = body.indexOf(
      endMarker,
      beginIndex >= 0
          ? beginIndex + beginMarker.length
          : 0,
    );

    if (beginIndex < 0 ||
        endIndex < 0 ||
        endIndex <= beginIndex) {
      return <String, dynamic>{};
    }

    var encodedJson = body.substring(
      beginIndex + beginMarker.length,
      endIndex,
    );

    // Apps Script cdhPostJsonResponse_() HTML-escapes the JSON.
    encodedJson = _htmlUnescape_(encodedJson).trim();

    try {
      final raw = jsonDecode(encodedJson);

      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // Return empty map so the caller produces the useful
      // HTTP/content-type/body diagnostic below.
    }

    return <String, dynamic>{};
  }

  /// Decodes the HTML entities used by the Apps Script response wrapper.
  static String _htmlUnescape_(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#38;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&#60;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#62;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }

  static bool _isRedirectStatus_(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static void _captureCookies_(
    HttpHeaders headers,
    Map<String, String> cookies,
  ) {
    final setCookies = headers['set-cookie'];
    if (setCookies == null) {
      return;
    }

    for (final value in setCookies) {
      final separator = value.indexOf(';');
      final cookiePart = separator >= 0
          ? value.substring(0, separator)
          : value;
      final equals = cookiePart.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final name = cookiePart.substring(0, equals).trim();
      final cookieValue = cookiePart.substring(equals + 1).trim();
      if (name.isNotEmpty) {
        cookies[name] = cookieValue;
      }
    }
  }

  static void _applyCookies_(
    HttpHeaders headers,
    Map<String, String> cookies,
  ) {
    if (cookies.isEmpty) {
      return;
    }

    headers.set(
      'Cookie',
      cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; '),
    );
  }

  static Future<http.Response> _sendPostNoRedirect_(
    HttpClient client,
    Uri uri,
    String requestBody,
    Map<String, String> cookies,
  ) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.contentType = ContentType.json;
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('User-Agent', 'CDH-Flutter-Client');
    _applyCookies_(request.headers, cookies);
    request.write(requestBody);

    final rawResponse = await request.close();
    _captureCookies_(rawResponse.headers, cookies);
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

  static Future<http.Response> _sendRedirectGet_(
    HttpClient client,
    Uri uri,
    Map<String, String> cookies,
  ) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set('Accept', 'application/json, text/plain, */*');
    request.headers.set('User-Agent', 'CDH-Flutter-Client');
    _applyCookies_(request.headers, cookies);

    final rawResponse = await request.close();
    _captureCookies_(rawResponse.headers, cookies);
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

  static Future<Map<String, dynamic>> getActiveOrder({
    required String product,
    required String planId,
  }) async {
    return _post({
      'action': 'getActiveOrder',
      'product': product,
      'planId': planId,
    });
  }
}
