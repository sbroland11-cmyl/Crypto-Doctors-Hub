import 'package:cloud_firestore/cloud_firestore.dart';

class ReferralService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection('referralSettings').doc('config');

  static Stream<Map<String, dynamic>> watchSettings() =>
      _settings.snapshots().map((snap) => snap.data() ?? <String, dynamic>{});

  static Future<Map<String, dynamic>> loadSettings() async {
    final snap = await _settings.get();
    return snap.data() ?? <String, dynamic>{};
  }

  static Future<String> buildReferralLink(String code) async {
    final clean = code.trim().toUpperCase();
    final settings = await loadSettings();
    var base = (settings['publicReferralUrl'] ?? '').toString().trim();

    // Firebase Hosting's project URL is used as a safe default until the
    // production referral/app-link URL is configured in referralSettings/config.
    if (base.isEmpty) {
      base = 'https://crypto-doctors-hub.web.app/';
    }

    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('The referral link URL is not configured correctly.');
    }

    final query = Map<String, String>.from(uri.queryParameters);
    query['ref'] = clean;
    return uri.replace(queryParameters: query).toString();
  }

  static Future<void> savePendingReferralForSignedInUser({
    required String uid,
    required String referralCode,
    required String referrerUid,
  }) async {
    if (uid == referrerUid) {
      throw StateError('Self-referrals are not allowed.');
    }
    await _db.collection('referralRelationships').doc(uid).set({
      'referredUid': uid,
      'referrerUid': referrerUid,
      'referralCode': referralCode.trim().toUpperCase(),
      'status': 'pending_qualification',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
