import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'drive_storage_service.dart';

class PaymentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> get _config => _db.collection('paymentSettings').doc('config');

  static Stream<Map<String, dynamic>> watchConfig() => _config.snapshots().map((snap) => snap.data() ?? <String, dynamic>{});

  static Future<Map<String, dynamic>> loadConfig() async {
    final snap = await _config.get();
    return snap.data() ?? <String, dynamic>{};
  }

  static Future<void> saveConfig({required List<Map<String, dynamic>> methods, required Map<String, dynamic> plans}) async {
    await _config.set({
      'paymentMethods': methods,
      'plans': plans,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static List<Map<String, dynamic>> defaultPaymentMethods() => [
    {'id': 'easypaisa', 'name': 'Easypaisa', 'type': 'Pakistan PKR', 'details': '', 'enabled': true},
    {'id': 'trc20', 'name': 'USDT TRC20', 'type': 'TRC20', 'details': '', 'enabled': true},
    {'id': 'bep20', 'name': 'USDT BEP20', 'type': 'BEP20', 'details': '', 'enabled': true},
    {'id': 'erc20', 'name': 'USDT ERC20', 'type': 'ERC20', 'details': '', 'enabled': true},
  ];

  static List<Map<String, dynamic>> _mergeDefaultMethods(List<Map<String, dynamic>> methods) {
    final merged = methods.map((e) => Map<String, dynamic>.from(e)).toList();
    for (final defaultMethod in defaultPaymentMethods()) {
      final index = merged.indexWhere((m) => (m['id'] ?? '').toString() == defaultMethod['id']);
      if (index < 0) merged.add(Map<String, dynamic>.from(defaultMethod));
    }
    return merged;
  }

  static Future<void> ensureDefaultPaymentMethods() async {
    final config = await loadConfig();
    final current = ((config['paymentMethods'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final merged = _mergeDefaultMethods(current);
    if (merged.length != current.length) {
      await saveConfig(
        methods: merged,
        plans: Map<String, dynamic>.from((config['plans'] as Map?) ?? {}),
      );
    }
  }

  static Future<void> saveMethod({required String id, required String name, required String type, required String details, required bool enabled}) async {
    final config = await loadConfig();
    final current = ((config['paymentMethods'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final methods = _mergeDefaultMethods(current);
    final index = methods.indexWhere((m) => (m['id'] ?? '').toString() == id);
    final value = <String, dynamic>{'id': id, 'name': name.trim(), 'type': type.trim(), 'details': details.trim(), 'enabled': enabled};
    if (index >= 0) {
      methods[index] = value;
    } else {
      methods.add(value);
    }
    await saveConfig(methods: methods, plans: Map<String, dynamic>.from((config['plans'] as Map?) ?? {}));
  }

  static Future<void> savePlan({required String id, required String name, required double amount, required String currency, required String description, required bool enabled}) async {
    final config = await loadConfig();
    final plans = Map<String, dynamic>.from((config['plans'] as Map?) ?? {});
    plans[id] = {'name': name.trim(), 'amount': amount, 'currency': currency.trim().isEmpty ? 'USD' : currency.trim().toUpperCase(), 'description': description.trim(), 'enabled': enabled};
    await saveConfig(
      methods: ((config['paymentMethods'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      plans: plans,
    );
  }

  static CollectionReference<Map<String, dynamic>> get _requests => _db.collection('paymentRequests');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMyRequests(String uid) =>
      _requests.where('uid', isEqualTo: uid).limit(20).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAdminRequests() =>
      _requests.orderBy('submittedAt', descending: true).limit(100).snapshots();

  static Future<String> notifyAdminIntent({
    required String uid,
    required String username,
    required String email,
    required String product,
    required String planId,
    required String planName,
    required double amount,
    required String currency,
    required String methodId,
    required String methodName,
    required String methodType,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Authentication session mismatch.');
    final ref = _requests.doc();
    await ref.set({
      'uid': uid,
      'username': username.trim().isEmpty ? 'User' : username.trim(),
      'email': email.trim(),
      'product': product.trim(),
      'planId': planId.trim(),
      'planName': planName.trim(),
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
      'paymentMethodId': methodId.trim(),
      'paymentMethodName': methodName.trim(),
      'paymentMethodType': methodType.trim(),
      'transactionReference': '',
      'proofUrl': '',
      'installmentNumber': 0,
      'status': 'intent',
      'intentAt': FieldValue.serverTimestamp(),
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<String> uploadPaymentProof({required String uid, required Uint8List bytes, required String extension}) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Payment screenshot is too large. Please choose an image under 5 MB.');
    }
    final ext = extension.toLowerCase().replaceAll('.', '');
    const allowed = {'jpg', 'jpeg', 'png', 'webp'};
    if (!allowed.contains(ext)) throw StateError('Only JPG, PNG or WEBP screenshots are allowed.');
    final contentType = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/$ext';
    final fileRef = await DriveStorageService.uploadBytes(
      bytes: bytes,
      fileName: '${DateTime.now().millisecondsSinceEpoch}.$ext',
      contentType: contentType,
      scope: 'payment_proof',
      ownerUid: uid,
    );
    return 'drive://$fileRef';
  }

  static Future<String> submitPaymentProof({
    required String uid,
    required String username,
    required String email,
    required String product,
    required String planId,
    required String planName,
    required double amount,
    required String currency,
    required String methodId,
    required String methodName,
    required String methodType,
    String transactionReference = '',
    String proofUrl = '',
    int installmentNumber = 0,
    String? requestId,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Authentication session mismatch.');
    final ref = requestId == null || requestId.trim().isEmpty ? _requests.doc() : _requests.doc(requestId.trim());
    final payload = <String, dynamic>{
      'uid': uid,
      'username': username.trim().isEmpty ? 'User' : username.trim(),
      'email': email.trim(),
      'product': product.trim(),
      'planId': planId.trim(),
      'planName': planName.trim(),
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
      'paymentMethodId': methodId.trim(),
      'paymentMethodName': methodName.trim(),
      'paymentMethodType': methodType.trim(),
      'transactionReference': transactionReference.trim(),
      'proofUrl': proofUrl.trim(),
      'installmentNumber': installmentNumber,
      'status': 'pending',
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (requestId == null || requestId.trim().isEmpty) {
      await ref.set(payload);
    } else {
      await ref.update({
        'transactionReference': transactionReference.trim(),
        'proofUrl': proofUrl.trim(),
        'installmentNumber': installmentNumber,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return ref.id;
  }

  static Future<void> adminApproveRequest(String requestId) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) throw StateError('Admin session required.');
    final token = await current.getIdTokenResult(true);
    if (token.claims?['admin'] != true) throw StateError('Admin access required.');

    final requestRef = _requests.doc(requestId);
    final snap = await requestRef.get();
    final data = snap.data();
    if (!snap.exists || data == null) throw StateError('Payment request not found.');
    if ((data['status'] ?? '').toString() != 'pending') throw StateError('This payment is already reviewed.');

    final uid = (data['uid'] ?? '').toString();
    final product = (data['product'] ?? '').toString();
    final planId = (data['planId'] ?? '').toString();
    if (uid.isEmpty) throw StateError('Payment request has no user ID.');

    final batch = _db.batch();
    final userRef = _db.collection('users').doc(uid);
    var requestUpdatedInsideTransaction = false;
    final now = FieldValue.serverTimestamp();

    if (product == 'premium') {
      final badgeType = planId == 'premium_one_time' ? 'premium_lifetime' : 'premium_monthly';
      batch.set(userRef, {
        'isPremium': true,
        'premiumStatus': 'approved',
        'premiumPlan': planId,
        'premiumApprovedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      final entitlement = userRef.collection('badgeEntitlements').doc(badgeType);
      batch.set(entitlement, {
        'badgeId': badgeType,
        'badgeType': badgeType,
        'eligible': true,
        'status': 'available',
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      batch.set(userRef.collection('mail').doc(), {
        'type': 'badge',
        'title': 'PREMIUM PAYMENT APPROVED',
        'body': 'Your Premium payment has been verified by Crypto Doctors Hub. Open Mail to collect your Premium badge.',
        'badgeIds': [badgeType],
        'badgeType': badgeType,
        'readAt': null,
        'createdAt': now,
      });
    } else if (product == 'verified_creator') {
      batch.set(userRef, {
        'verifiedCreatorApproved': true,
        'verifiedCreatorPaymentStatus': 'approved',
        'verifiedCreatorPlan': planId,
        'verifiedCreatorApprovedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
      batch.set(userRef.collection('mail').doc(), {
        'type': 'verification',
        'title': 'VERIFIED CREATOR PAYMENT APPROVED',
        'body': 'Your Verified Creator payment has been verified. Your application can now continue through the Admin approval process.',
        'readAt': null,
        'createdAt': now,
      });
    } else if (product == 'mentorship') {
      if (planId == 'mentorship_installment') {
        await _db.runTransaction((tx) async {
          final requestSnap = await tx.get(requestRef);
          final requestData = requestSnap.data();
          if (!requestSnap.exists || requestData == null || (requestData['status'] ?? '').toString() != 'pending') {
            throw StateError('This payment request is already reviewed or no longer pending.');
          }
          final paymentRef = _db.collection('mentorshipPayments').doc(uid);
          final paymentSnap = await tx.get(paymentRef);
          final payment = paymentSnap.data() ?? <String, dynamic>{};
          final paidWeeks = (payment['paidWeeks'] as num?)?.toInt() ?? 0;
          if (paidWeeks >= 4) throw StateError('All four Mentorship installments are already approved.');
          final newPaidWeeks = paidWeeks + 1;
          final completed = newPaidWeeks >= 4;
          final nowDate = DateTime.now();
          tx.set(paymentRef, {
            'uid': uid,
            'plan': 'installment',
            'totalAmount': 80,
            'weeklyAmount': 20,
            'weeks': 4,
            'paidWeeks': newPaidWeeks,
            'paymentStatus': completed ? 'completed' : 'current',
            'lastInstallmentPaidAt': Timestamp.fromDate(nowDate),
            if (!completed) 'nextInstallmentDueAt': Timestamp.fromDate(nowDate.add(const Duration(days: 7))),
            if (completed) 'nextInstallmentDueAt': FieldValue.delete(),
            'updatedAt': now,
          }, SetOptions(merge: true));
          tx.set(userRef, {
            'mentorshipApproved': true,
            'studentApproved': true,
            'isStudent': true,
            'studentStatus': 'Student',
            'mentorshipPaymentPlan': 'installment',
            'mentorshipPaymentStatus': completed ? 'completed' : 'current',
            'installmentPaidWeeks': newPaidWeeks,
            'lastInstallmentPaidAt': Timestamp.fromDate(nowDate),
            if (!completed) 'installmentNextDueAt': Timestamp.fromDate(nowDate.add(const Duration(days: 7))),
            if (completed) 'installmentNextDueAt': FieldValue.delete(),
            'updatedAt': now,
          }, SetOptions(merge: true));
          final badgeType = 'mentorship_installment_$newPaidWeeks';
          tx.set(userRef.collection('badgeEntitlements').doc(badgeType), {
            'badgeId': badgeType,
            'badgeType': badgeType,
            'eligible': true,
            'status': 'available',
            'studentStage': newPaidWeeks,
            'graduated': false,
            'createdAt': now,
            'updatedAt': now,
          }, SetOptions(merge: true));
          tx.update(requestRef, {
            'status': 'approved',
            'reviewedAt': now,
            'reviewedBy': current.uid,
            'updatedAt': now,
          });
          requestUpdatedInsideTransaction = true;
          tx.set(userRef.collection('mail').doc(), {
            'type': 'badge',
            'title': 'MENTORSHIP INSTALLMENT $newPaidWeeks PAID',
            'body': 'Your Mentorship installment $newPaidWeeks has been verified. Open Mail to collect your Student $newPaidWeeks badge. Student 4 is separate from Graduated.',
            'badgeIds': [badgeType],
            'badgeType': badgeType,
            'studentStage': newPaidWeeks,
            'graduated': false,
            'readAt': null,
            'createdAt': now,
          });
        });
      } else {
        batch.set(userRef, {
          'mentorshipApproved': true,
          'studentApproved': true,
          'isStudent': true,
          'studentStatus': 'Student',
          'mentorshipPaymentPlan': 'one_time',
          'mentorshipPaymentStatus': 'completed',
          'mentorshipApprovedAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
        batch.set(userRef.collection('badgeEntitlements').doc('mentorship_one_time'), {
          'badgeId': 'mentorship_one_time',
          'badgeType': 'mentorship_one_time',
          'eligible': true,
          'status': 'available',
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
        batch.set(userRef.collection('mail').doc(), {
          'type': 'badge',
          'title': 'MENTORSHIP PAYMENT APPROVED',
          'body': 'Your Mentorship payment has been verified. Open Mail to collect your Student badge.',
          'badgeIds': ['mentorship_one_time'],
          'badgeType': 'mentorship_one_time',
          'readAt': null,
          'createdAt': now,
        });
      }
    } else {
      throw StateError('Unsupported payment product.');
    }

    if (!requestUpdatedInsideTransaction) {
      batch.update(requestRef, {
        'status': 'approved',
        'reviewedAt': now,
        'reviewedBy': current.uid,
        'updatedAt': now,
      });
      await batch.commit();
    }
  }

  static Future<void> adminRejectRequest(String requestId, {String reason = ''}) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) throw StateError('Admin session required.');
    final token = await current.getIdTokenResult(true);
    if (token.claims?['admin'] != true) throw StateError('Admin access required.');
    await _requests.doc(requestId).update({
      'status': 'rejected',
      'rejectionReason': reason.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': current.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

}
