import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Badge entitlement and Mail access layer.
///
/// Payment verification/entitlement creation is backend-owned. The client
/// can only read backend-created entitlements, collect an eligible badge,
/// and confirm a badge that has already been collected.
class BadgeService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _entitlements(String uid) =>
      _db.collection('users').doc(uid).collection('badgeEntitlements');

  static CollectionReference<Map<String, dynamic>> _mail(String uid) =>
      _db.collection('users').doc(uid).collection('mail');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMail(String uid) =>
      _mail(uid).orderBy('createdAt', descending: true).limit(100).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchBadgeEntitlements(String uid) =>
      _entitlements(uid).snapshots();


  static CollectionReference<Map<String, dynamic>> get _graduatedInventory =>
      _db.collection('graduatedBadgeInventory');

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchGraduatedBadgeInventory() =>
      _graduatedInventory.orderBy('badgeNumber').snapshots();

  static Future<void> ensureGraduatedBadgeInventory() async {
    final existing = await _graduatedInventory.get();
    final batch = _db.batch();
    for (var number = 1; number <= 25; number++) {
      final id = 'graduated_${number.toString().padLeft(2, '0')}';
      if (!existing.docs.any((doc) => doc.id == id)) {
        batch.set(_graduatedInventory.doc(id), {
          'badgeNumber': number,
          'title': 'GRADUATED BADGE #${number.toString().padLeft(2, '0')}',
          'status': 'available',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  static Future<void> grantGraduatedBadge({
    required int badgeNumber,
    required String targetUid,
  }) async {
    if (badgeNumber < 1 || badgeNumber > 25) {
      throw StateError('Graduated badge number must be between 1 and 25.');
    }
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) throw StateError('Admin session is missing.');
    final token = await admin.getIdTokenResult(true);
    if (token.claims?['admin'] != true) throw StateError('Admin authorization required.');

    final uid = targetUid.trim();
    if (uid.isEmpty) throw StateError('Select a user first.');

    final inventoryId = 'graduated_${badgeNumber.toString().padLeft(2, '0')}';
    final inventoryRef = _graduatedInventory.doc(inventoryId);
    final userRef = _db.collection('users').doc(uid);
    final entitlementId = 'graduated_admin_$inventoryId';
    final entitlementRef = userRef.collection('badgeEntitlements').doc(entitlementId);
    final mailRef = userRef.collection('mail').doc('mail_$entitlementId');

    await _db.runTransaction<void>((tx) async {
      final inventorySnap = await tx.get(inventoryRef);
      final userSnap = await tx.get(userRef);
      if (!inventorySnap.exists) throw StateError('Graduated badge inventory is not initialized.');
      if (!userSnap.exists) throw StateError('Target user was not found.');
      final inventory = inventorySnap.data() ?? <String, dynamic>{};
      if ((inventory['status'] ?? '').toString() != 'available') {
        throw StateError('Graduated Badge #$badgeNumber has already been assigned.');
      }
      final userData = userSnap.data() ?? <String, dynamic>{};
      if (userData['graduated'] == true) {
        throw StateError('This user already has a Graduated status.');
      }
      final entitlementSnap = await tx.get(entitlementRef);
      if (entitlementSnap.exists) throw StateError('This graduated badge entitlement already exists for the user.');

      final title = 'GRADUATED BADGE #${badgeNumber.toString().padLeft(2, '0')}';
      tx.set(entitlementRef, {
        'badgeId': entitlementId,
        'badgeType': 'graduated_admin',
        'title': title,
        'description': 'Official Graduated badge assigned by CDH Admin.',
        'eligible': true,
        'status': 'available',
        'source': 'admin_graduated_badge',
        'inventoryBadgeNumber': badgeNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(mailRef, {
        'type': 'badge',
        'title': '$title AVAILABLE',
        'body': 'Admin has awarded you an official Graduated badge. Open this message to collect it and place the black graduation cap on your profile.',
        'badgeIds': [entitlementId],
        'readAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(inventoryRef, {
        'status': 'assigned',
        'assignedToUid': uid,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignedByUid': admin.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> markMailRead(String uid, String messageId) async {
    await _mail(uid).doc(messageId).update({
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, dynamic>> collectBadge({
    required String uid,
    required String badgeId,
  }) async {
    final ref = _entitlements(uid).doc(badgeId);
    return _db.runTransaction<Map<String, dynamic>>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (!snap.exists || data == null) {
        throw StateError('Badge entitlement was not found.');
      }
      if (data['eligible'] != true) {
        throw StateError('This badge is not eligible for collection.');
      }
      if ((data['status'] ?? '').toString() != 'available') {
        throw StateError('This badge has already been collected.');
      }
      tx.update(ref, {
        'status': 'collected',
        'collectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if ((data['source'] ?? '').toString() == 'admin_graduated_badge' &&
          (data['badgeType'] ?? '').toString() == 'graduated_admin') {
        final userRef = _db.collection('users').doc(uid);
        tx.set(userRef, {
          'graduated': true,
          'graduatedBadgeId': badgeId,
          'graduatedAt': FieldValue.serverTimestamp(),
          'graduatedBadgeType': 'graduated_admin',
          'badgesUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return Map<String, dynamic>.from(data)..['status'] = 'collected';
    });
  }

  static Future<void> confirmBadge({
    required String uid,
    required String badgeId,
    required String badgeType,
  }) async {
    final entitlementRef = _entitlements(uid).doc(badgeId);
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction<void>((tx) async {
      final entitlement = await tx.get(entitlementRef);
      final data = entitlement.data();
      if (!entitlement.exists || data == null) {
        throw StateError('Badge entitlement was not found.');
      }
      if (data['eligible'] != true || (data['status'] ?? '').toString() != 'collected') {
        throw StateError('Collect the badge before confirming it.');
      }
      if ((data['badgeType'] ?? '').toString() != badgeType) {
        throw StateError('Badge type does not match the entitlement.');
      }

      tx.update(entitlementRef, {
        'status': 'confirmed',
        'confirmedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (badgeType == 'graduated_admin') {
        tx.set(userRef, {
          'graduated': true,
          'graduatedBadgeId': badgeId,
          'graduatedBadgeType': 'graduated_admin',
          'graduatedAt': FieldValue.serverTimestamp(),
          'badgesUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final profileField = badgeType.startsWith('premium_')
            ? 'confirmedPremiumBadgeType'
            : badgeType.startsWith('referral_crown_')
                ? 'confirmedReferralCrownType'
                : 'confirmedMentorshipBadgeType';
        tx.set(userRef, {
          profileField: badgeType,
          'badgesUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }
}
