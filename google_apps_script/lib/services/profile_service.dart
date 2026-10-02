import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);

  static Future<Map<String, dynamic>?> loadUserProfile(String uid) async {
    final snap = await _user(uid).get();
    return snap.data();
  }

  static String referralCodeForUid(String uid) {
    final clean = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return clean.length >= 8 ? clean.substring(0, 8) : clean.padRight(8, 'X');
  }

  static Future<String> ensureReferralCode(String uid) async {
    final ref = _user(uid);
    final snap = await ref.get();
    final existing = (snap.data()?['referralCode'] ?? '').toString().trim();
    if (existing.isNotEmpty) return existing;
    final code = referralCodeForUid(uid);
    await ref.set({'referralCode': code, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return code;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchAppAvatar({required String uid}) => _user(uid).collection('appAvatar').doc('current').snapshots();

  static Future<String> loadAppAvatar({required String uid}) async {
    final avatar = await _user(uid).collection('appAvatar').doc('current').get();
    final value = (avatar.data()?['imageBase64'] ?? '').toString();
    if (value.isNotEmpty) return value;
    final profile = await _user(uid).get();
    return (profile.data()?['appAvatarBase64'] ?? '').toString();
  }

  static Future<void> saveThemePreference({required String uid, required String preference}) async {
    await _user(uid).set({'themePreference': preference, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>?> loadReferralPaymentDetails({required String uid}) async {
    final snap = await _db.collection('referral_payment_details').doc(uid).get();
    return snap.data();
  }

  static Future<void> saveReferralPaymentDetails({required String uid, required String country, required String preferredMethod, required String recipientName, required String usdtTrc20Address, required String usdtBep20Address, required String usdtErc20Address, required String easypaisaNumber}) async {
    await _db.collection('referral_payment_details').doc(uid).set({
      'country': country, 'preferredMethod': preferredMethod, 'recipientName': recipientName,
      'usdtTrc20Address': usdtTrc20Address, 'usdtBep20Address': usdtBep20Address,
      'usdtErc20Address': usdtErc20Address, 'easypaisaNumber': easypaisaNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
