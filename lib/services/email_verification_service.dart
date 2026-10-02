import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class EmailVerificationService {
  static const String _endpoint =
      'https://script.google.com/macros/s/AKfycbzMvodYlFaFeFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec';

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final client = HttpClient();
    final cookies = <String, String>{};
    http.Response response;

    try {
      response = await _sendPostNoRedirect_(
        client,
        Uri.parse(_endpoint),
        jsonEncode(body),
        cookies,
      );

      var redirectCount = 0;
      while (_isRedirectStatus_(response.statusCode)) {
        redirectCount++;
        if (redirectCount > 8) {
          throw StateError('Verification service redirected too many times.');
        }

        final location = response.headers['location'];
        if (location == null || location.isEmpty) {
          throw StateError('Verification service redirected without a Location header.');
        }

        final redirectUri = response.request?.url.resolve(location) ?? Uri.parse(location);
        response = await _sendRedirectGet_(client, redirectUri, cookies);
      }
    } finally {
      client.close(force: true);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Verification service returned HTTP ${response.statusCode}.');
    }

    final rawBody = response.body.trim();
    if (rawBody.isEmpty) {
      throw StateError('Verification service returned an empty response.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (_) {
      throw StateError(
        'Verification service returned HTML instead of JSON. Check that the Apps Script deployment URL is the deployed /exec URL and that the deployment is accessible to the app.',
      );
    }

    if (decoded is! Map) {
      throw StateError('Verification service returned an invalid response.');
    }

    final data = Map<String, dynamic>.from(decoded);
    if (data['success'] != true) {
      throw StateError((data['message'] ?? 'Verification request failed.').toString());
    }
    return data;
  }

  static bool _isRedirectStatus_(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static void _captureCookies_(HttpHeaders headers, Map<String, String> cookies) {
    final setCookies = headers['set-cookie'];
    if (setCookies == null) return;
    for (final value in setCookies) {
      final separator = value.indexOf(';');
      final cookiePart = separator >= 0 ? value.substring(0, separator) : value;
      final equals = cookiePart.indexOf('=');
      if (equals <= 0) continue;
      final name = cookiePart.substring(0, equals).trim();
      final cookieValue = cookiePart.substring(equals + 1).trim();
      if (name.isNotEmpty) cookies[name] = cookieValue;
    }
  }

  static void _applyCookies_(HttpHeaders headers, Map<String, String> cookies) {
    if (cookies.isEmpty) return;
    headers.set('Cookie', cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '));
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
    rawResponse.headers.forEach((name, values) => headers[name] = values.join(', '));

    return http.Response(body, rawResponse.statusCode, headers: headers, request: http.Request('POST', uri));
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
    rawResponse.headers.forEach((name, values) => headers[name] = values.join(', '));

    return http.Response(body, rawResponse.statusCode, headers: headers, request: http.Request('GET', uri));
  }

  static Future<String> startSignup({required String email}) async =>
      (await _post({'action':'startSignupEmailCode','email':email.trim().toLowerCase()}))['attemptId'].toString();

  static Future<bool> verifySignup({required String attemptId, required String email, required String code}) async =>
      (await _post({'action':'verifySignupEmailCode','attemptId':attemptId,'email':email.trim().toLowerCase(),'code':code.trim()}))['verified'] == true;

  static Future<String> finalizeSignup({required String attemptId, required String email, required String password}) async =>
      (await _post({'action':'finalizeSignupEmailVerification','attemptId':attemptId,'email':email.trim().toLowerCase(),'password':password}))['customToken'].toString();

  static Future<String> startLogin({required String email}) async =>
      (await _post({'action':'startLoginEmailCode','email':email.trim().toLowerCase()}))['attemptId'].toString();

  static Future<bool> verifyLogin({required String attemptId, required String email, required String code}) async =>
      (await _post({'action':'verifyLoginEmailCode','attemptId':attemptId,'email':email.trim().toLowerCase(),'code':code.trim()}))['verified'] == true;

  static Future<String> completeLogin({required String attemptId, required String email, required String password}) async =>
      (await _post({'action':'completeLoginAfterEmailVerification','attemptId':attemptId,'email':email.trim().toLowerCase(),'password':password}))['customToken'].toString();

  static Future<String> startPasswordReset({required String email}) async =>
      (await _post({'action':'startPasswordResetEmailCode','email':email.trim().toLowerCase()}))['attemptId'].toString();

  static Future<bool> verifyPasswordReset({required String attemptId, required String email, required String code}) async =>
      (await _post({'action':'verifyPasswordResetEmailCode','attemptId':attemptId,'email':email.trim().toLowerCase(),'code':code.trim()}))['verified'] == true;

  static Future<String> resetPassword({required String attemptId, required String email, required String newPassword}) async =>
      (await _post({'action':'resetPasswordAfterEmailVerification','attemptId':attemptId,'email':email.trim().toLowerCase(),'newPassword':newPassword}))['customToken'].toString();
}
