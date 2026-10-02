import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Backend/Firebase bridge for central subscription payments.
///
/// Crypto automatic payment verification remains owned by
/// AutomaticPaymentService. This service handles configuration plus the
/// separate manual Easypaisa proof/review workflow.
class PaymentService {
  static const String endpoint = String.fromEnvironment(
    'CDH_DRIVE_BACKEND_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzMvodYlFaFEFEfPCYoWeZyA9hXWM7rm_r3O2Bp7sAQwKMZprQabvfML7zAmBXhItOHvA/exec',
  );

  static CollectionReference<Map<String, dynamic>> get _requests => FirebaseFirestore.instance.collection('paymentRequests');
  static DocumentReference<Map<String, dynamic>> get _config => FirebaseFirestore.instance.collection('paymentSettings').doc('config');

  static List<Map<String, dynamic>> defaultPaymentMethods() => const [
        {'id': 'trc20', 'name': 'USDT TRC20', 'type': 'TRC20', 'details': '', 'enabled': true},
        {'id': 'bep20', 'name': 'USDT BEP20', 'type': 'BEP20', 'details': '', 'enabled': true},
        {'id': 'erc20', 'name': 'USDT ERC20', 'type': 'ERC20', 'details': '', 'enabled': true},
        {'id': 'easypaisa', 'name': 'Easypaisa', 'type': 'Easypaisa', 'details': '', 'enabled': true},
      ];

  static Stream<Map<String, dynamic>> watchConfig() => _config.snapshots().map((snap) => snap.data() ?? <String, dynamic>{});

  static Future<Map<String, dynamic>> loadConfig() async => (await _config.get()).data() ?? <String, dynamic>{};

  static Future<void> ensureDefaultPaymentMethods() async {
    final snap = await _config.get();
    if (snap.exists && (snap.data()?['paymentMethods'] as List?)?.isNotEmpty == true) return;
    if (snap.exists) return;
    await _config.set({'paymentMethods': defaultPaymentMethods(), 'plans': <String, dynamic>{}}, SetOptions(merge: true));
  }

  static Future<void> saveMethod({required String id, required String name, required String type, required String details, required bool enabled}) async {
    final current = await loadConfig();
    final methods = ((current['paymentMethods'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final index = methods.indexWhere((m) => (m['id'] ?? '').toString() == id);
    final value = {'id': id, 'name': name, 'type': type, 'details': details, 'enabled': enabled};
    if (index >= 0) {
      methods[index] = value;
    } else {
      methods.add(value);
    }
    await _config.set({'paymentMethods': methods}, SetOptions(merge: true));
  }

  static Future<void> savePlan({required String id, required String name, required double amount, required String currency, required String description, required bool enabled}) async {
    await _config.set({'plans': {id: {'name': name, 'amount': amount, 'currency': currency, 'description': description, 'enabled': enabled}}}, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMyRequests(String uid) => _requests.where('uid', isEqualTo: uid).orderBy('submittedAt', descending: true).snapshots();
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAdminRequests() => _requests.orderBy('submittedAt', descending: true).snapshots();

  static Future<String> uploadPaymentProof({required String uid, required Uint8List bytes, required String extension}) async {
    final safeExt = extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final name = 'payment_proof_${DateTime.now().millisecondsSinceEpoch}.${safeExt.isEmpty ? 'jpg' : safeExt}';
    final encoded = base64Encode(bytes);
    final result = await _post({
      'action': 'uploadPaymentProof',
      'uid': uid,
      'fileName': name,
      'contentType': _contentType(safeExt),
      'base64Data': encoded,
    });
    final proofUrl = (result['proofUrl'] ?? '').toString();
    if (proofUrl.isEmpty) throw StateError('Backend did not return a payment proof URL.');
    return proofUrl;
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }

  static Future<String> notifyAdminIntent({required String uid, required String username, required String email, required String product, required String planId, required String planName, required double amount, required String currency, required String methodId, required String methodName, required String methodType}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) throw StateError('Authentication required.');
    final ref = _requests.doc();
    await ref.set({
      'uid': uid, 'username': username, 'email': email, 'product': product, 'planId': planId, 'planName': planName,
      'amount': amount, 'currency': currency, 'paymentMethodId': methodId, 'paymentMethodName': methodName, 'paymentMethodType': methodType,
      'status': 'intent', 'createdAt': FieldValue.serverTimestamp(), 'submittedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<String> submitPaymentProof({required String uid, required String username, required String email, required String product, required String planId, required String planName, required double amount, required String currency, required String methodId, required String methodName, required String methodType, required String paymentDetails, required String proofUrl, required String transactionReference, required int installmentNumber}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) throw StateError('Authentication required.');
    if (!methodId.toLowerCase().contains('easypaisa') && !methodName.toLowerCase().contains('easypaisa')) throw StateError('Payment proof is only supported for Easypaisa.');
    final duplicate = await _requests.where('uid', isEqualTo: uid).where('status', whereIn: ['awaiting_admin_verification', 'completed']).limit(20).get();
    for (final doc in duplicate.docs) {
      final d = doc.data();
      if ((d['planId'] ?? '') == planId && (d['status'] ?? '') == 'awaiting_admin_verification') return doc.id;
    }
    return _backendSubmitProof(
      uid: uid, username: username, email: email, product: product, planId: planId, planName: planName,
      amount: amount, currency: currency, methodId: methodId, methodName: methodName, methodType: methodType, paymentDetails: paymentDetails,
      proofUrl: proofUrl, transactionReference: transactionReference, installmentNumber: installmentNumber,
    );
  }

  static Future<String> _backendSubmitProof({required String uid, required String username, required String email, required String product, required String planId, required String planName, required double amount, required String currency, required String methodId, required String methodName, required String methodType, required String paymentDetails, required String proofUrl, required String transactionReference, required int installmentNumber}) async {
    final result = await _post({
      'action': 'submitEasypaisaSubscriptionProof', 'uid': uid, 'username': username, 'email': email, 'product': product,
      'planId': planId, 'planName': planName, 'amount': amount, 'currency': currency, 'paymentMethodId': methodId,
      'paymentMethodName': methodName, 'paymentMethodType': methodType, 'paymentDetails': paymentDetails, 'proofUrl': proofUrl, 'transactionReference': transactionReference,
      'installmentNumber': installmentNumber,
    });
    final id = (result['requestId'] ?? result['paymentRequestId'] ?? '').toString();
    if (id.isEmpty) throw StateError('Backend did not return a payment request ID.');
    return id;
  }

  static Future<void> adminApproveRequest(String requestId) async {
    final result = await _post({'action': 'adminConfirmEasypaisaSubscriptionPayment', 'requestId': requestId});
    if (result['success'] != true) throw StateError((result['message'] ?? result['error'] ?? 'Payment confirmation failed.').toString());
  }

  static Future<void> adminRejectRequest(String requestId, {String reason = ''}) async {
    final result = await _post({'action': 'adminRejectEasypaisaSubscriptionPayment', 'requestId': requestId, 'reason': reason});
    if (result['success'] != true) throw StateError((result['message'] ?? result['error'] ?? 'Payment rejection failed.').toString());
  }

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Authentication required.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Could not obtain Firebase authentication token.');
    final payload = jsonEncode({...body, 'idToken': token});
    final client = HttpClient();
    try {
      var response = await _postNoRedirect(client, Uri.parse(endpoint), payload);
      var redirects = 0;
      while ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        if (++redirects > 8) throw StateError('Backend redirected too many times.');
        final location = response.headers['location'];
        if (location == null || location.isEmpty) throw StateError('Backend redirect has no location.');
        final next = response.request?.url.resolve(location) ?? Uri.parse(location);
        response = await _get(client, next);
      }
      Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(response.body);
        decoded = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      } catch (_) {
        decoded = <String, dynamic>{};
      }
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
        throw StateError((decoded['message'] ?? decoded['error'] ?? 'Backend request failed (${response.statusCode}).').toString());
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
    final response = await request.close();
    return http.Response(await response.transform(utf8.decoder).join(), response.statusCode, headers: _headers(response.headers), request: http.Request('POST', uri));
  }

  static Future<http.Response> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set('Accept', 'application/json, text/plain, */*');
    final response = await request.close();
    return http.Response(await response.transform(utf8.decoder).join(), response.statusCode, headers: _headers(response.headers), request: http.Request('GET', uri));
  }

  static Map<String, String> _headers(HttpHeaders headers) {
    final out = <String, String>{};
    headers.forEach((name, values) => out[name] = values.join(', '));
    return out;
  }
}
