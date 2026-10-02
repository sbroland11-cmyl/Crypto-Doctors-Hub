import 'package:cloud_firestore/cloud_firestore.dart';

class PayoutService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('user_payout_details');

  static Future<Map<String, dynamic>?> load({required String uid}) async {
    final snap = await _collection.doc(uid).get();
    return snap.data();
  }

  static Future<void> save({
    required String uid,
    required String userName,
    required String paymentMethod,
    required String paymentDetail,
  }) async {
    await _collection.doc(uid).set({
      'uid': uid,
      'userName': userName,
      'paymentMethod': paymentMethod,
      'paymentDetail': paymentDetail,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAll() =>
      _collection.limit(500).snapshots();
}
