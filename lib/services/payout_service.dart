import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Backend-owned payout details and payout-request bridge.
///
/// The client never marks a payout paid/credited. Apps Script verifies the
/// Firebase identity and owns payout status transitions/accounting.
class PayoutService {
  static const String endpoint = String.fromEnvironment(
    'CDH_DRIVE_BACKEND_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzMvodYlFaFEFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec',
  );

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _collection => _db.collection('user_payout_details');

  static Future<Map<String, dynamic>?> load({required String uid}) async {
    final snap = await _collection.doc(uid).get();
    return snap.data();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAll() => _collection.limit(500).snapshots();

  static Uri _uri() => Uri.parse(endpoint);

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Authentication required.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Could not obtain Firebase authentication token.');
    final payload = <String, dynamic>{...body, 'idToken': token};
    final client = HttpClient();
    try {
      var response = await _postNoRedirect(client, _uri(), jsonEncode(payload));
      var redirects = 0;
      while ({301,302,303,307,308}.contains(response.statusCode)) {
        if (++redirects > 8) throw StateError('Payout backend redirected too many times.');
        final location = response.headers['location'];
        if (location == null || location.isEmpty) throw StateError('Payout backend redirected without Location.');
        response = await _getRedirect(client, response.request?.url.resolve(location) ?? Uri.parse(location));
      }
      Map<String, dynamic> decoded = {};
      try {
        final raw = jsonDecode(response.body);
        if (raw is Map) decoded = Map<String, dynamic>.from(raw);
      } catch (_) {}
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
        throw StateError((decoded['message'] ?? decoded['error'] ?? 'Payout backend failed (${response.statusCode}).').toString());
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  static Future<http.Response> _postNoRedirect(HttpClient client, Uri uri, String body) async {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json');
    request.write(body);
    final raw = await request.close();
    final text = await raw.transform(utf8.decoder).join();
    final headers = <String, String>{};
    raw.headers.forEach((k,v) => headers[k] = v.join(', '));
    return http.Response(text, raw.statusCode, headers: headers, request: http.Request('POST', uri));
  }

  static Future<http.Response> _getRedirect(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final raw = await request.close();
    final text = await raw.transform(utf8.decoder).join();
    final headers = <String, String>{};
    raw.headers.forEach((k,v) => headers[k] = v.join(', '));
    return http.Response(text, raw.statusCode, headers: headers, request: http.Request('GET', uri));
  }

  static Future<void> save({required String uid, required String userName, required String paymentMethod, required String paymentDetail}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Authentication required.');
    }

    final safeUserName = userName.trim();
    final safeMethod = paymentMethod.trim();
    final safeDetail = paymentDetail.trim();

    if (safeUserName.isEmpty) throw StateError('User name is required.');
    if (safeMethod.isEmpty) throw StateError('Payment method is required.');
    if (safeDetail.isEmpty) throw StateError('Payment details are required.');
    if (safeDetail.length > 500) throw StateError('Payment details are too long.');

    // Saving the user's own payout details is already explicitly permitted by
    // the existing Firestore rules when the document is locked=true. Doing
    // this write directly avoids the Apps Script web-app response/redirect
    // layer, which is currently capable of returning HTTP 404 after doPost()
    // has successfully executed. The backend remains responsible for payout
    // requests, accounting, and payment status transitions.
    await _collection.doc(uid).set({
      'uid': uid,
      'userName': safeUserName,
      'paymentMethod': safeMethod,
      'paymentDetail': safeDetail,
      'locked': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  static Future<void> unlock({required String uid}) async {
    final result = await _post({'action': 'unlockPayoutDetails', 'uid': uid});
    if (result['unlocked'] != true) throw StateError('Payout details could not be unlocked.');
  }

  static Future<Map<String, dynamic>> createPayoutRequest({required String uid}) => _post({'action': 'createPayoutRequest', 'uid': uid});

  static Future<Map<String, dynamic>> getPayoutRequest(String payoutRequestId) => _post({'action': 'getPayoutRequest', 'payoutRequestId': payoutRequestId});

  static Future<Map<String, dynamic>> adminConfirmEasypaisaPayout({required String payoutRequestId}) => _post({'action': 'adminConfirmEasypaisaPayout', 'payoutRequestId': payoutRequestId});

  static Future<List<Map<String, dynamic>>> adminListPayoutRequests() async {
    final result = await _post({'action': 'adminListPayoutRequests'});
    return ((result['payouts'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
