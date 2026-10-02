import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'drive_storage_service.dart';

class MentorshipService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _lessons => _db.collection('mentorshipLessons');
  static CollectionReference<Map<String, dynamic>> get _payments => _db.collection('mentorshipPayments');
  static CollectionReference<Map<String, dynamic>> get _students => _db.collection('mentorshipStudents');
  static CollectionReference<Map<String, dynamic>> get _schedules => _db.collection('mentorshipSchedules');
  static CollectionReference<Map<String, dynamic>> get _reminders => _db.collection('mentorshipReminders');
  static CollectionReference<Map<String, dynamic>> get _studentDirectory => _db.collection('mentorshipStudentDirectory');
  static CollectionReference<Map<String, dynamic>> get _chatMessages => _db.collection('mentorshipChatMessages');
  static CollectionReference<Map<String, dynamic>> get _chatMembers => _db.collection('mentorshipChatMembers');
  static CollectionReference<Map<String, dynamic>> get _chatModeration => _db.collection('mentorshipChatModeration');

  static Future<Map<String, dynamic>?> loadChatMember(String uid) async {
    final snap = await _chatMembers.doc(uid).get();
    return snap.data();
  }

  static Future<void> ensureChatMember({required String uid, required String name}) async {
    final ref = _chatMembers.doc(uid);
    final snap = await ref.get();
    final cleanName = name.trim().isEmpty ? 'Mentorship Student' : name.trim();
    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'name': cleanName,
        'active': true,
        'banned': false,
        'restrictedUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    // Never let a normal student client restore its own removed/banned access.
    await ref.set({'uid': uid, 'name': cleanName, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> mentorshipChatStream() =>
      _chatMessages.orderBy('createdAt', descending: true).limit(100).snapshots();

  static String newChatMessageId() => _chatMessages.doc().id;

  static Future<void> sendChatMessage({
    required String uid,
    required String name,
    String text = '',
    String? imageUrl,
    String? messageId,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty && (imageUrl == null || imageUrl.isEmpty)) {
      throw ArgumentError('Message cannot be empty.');
    }
    final memberRef = _chatMembers.doc(uid);
    final messageRef = messageId == null ? _chatMessages.doc() : _chatMessages.doc(messageId);
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
    final isAdmin = token?.claims?['admin'] == true;
    if (!isAdmin) {
      final userSnap = await _db.collection('users').doc(uid).get();
      final user = userSnap.data() ?? <String, dynamic>{};
      final activeMentorship = user['mentorshipApproved'] == true || user['studentApproved'] == true || user['isStudent'] == true;
      if (!activeMentorship) throw StateError('You do not currently have access to the Mentorship Chat Room.');
    }
    await _db.runTransaction((tx) async {
      final memberSnap = await tx.get(memberRef);
      final member = memberSnap.data() ?? <String, dynamic>{};
      if (!isAdmin && (member['banned'] == true || member['active'] == false)) {
        throw StateError('You do not currently have access to the Mentorship Chat Room.');
      }
      final restrictedUntil = member['restrictedUntil'];
      if (restrictedUntil is Timestamp && restrictedUntil.toDate().isAfter(DateTime.now())) {
        throw StateError('Messaging is temporarily restricted.');
      }
      final lastSent = member['lastMessageAt'];
      if (!isAdmin && lastSent is Timestamp) {
        final elapsed = DateTime.now().difference(lastSent.toDate()).inMilliseconds;
        if (elapsed < 5000) {
          throw StateError('Please wait ${((5000 - elapsed + 999) ~/ 1000)} seconds before sending again.');
        }
      }
      tx.set(messageRef, {
        'uid': uid,
        'senderUid': uid,
        'senderName': name.trim().isEmpty ? 'Mentorship Student' : name.trim(),
        'text': cleanText,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        'reactions': <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(memberRef, {
        'uid': uid,
        'name': name.trim().isEmpty ? 'Mentorship Student' : name.trim(),
        'active': true,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<String> uploadChatScreenshot({required String uid, required Uint8List bytes, required String extension}) async {
    if (bytes.length > 900000) throw StateError('Screenshot is too large. Please choose a smaller image.');
    final safeExt = extension.toLowerCase().replaceAll('.', '');
    const allowed = {'jpg', 'jpeg', 'png', 'webp'};
    if (!allowed.contains(safeExt)) throw StateError('Only screenshot/image files are allowed.');
    final fileRef = await DriveStorageService.uploadBytes(
      bytes: bytes,
      fileName: '${DateTime.now().millisecondsSinceEpoch}.$safeExt',
      contentType: 'image/$safeExt',
      scope: 'mentorship_chat',
      ownerUid: uid,
    );
    return 'drive://$fileRef';
  }

  static Future<void> setChatReaction({required String messageId, required String uid, required String reaction}) async {
    if (reaction.trim().isEmpty) return;
    await _chatMessages.doc(messageId).update({'reactions.$uid': reaction});
  }

  static Future<void> removeChatReaction({required String messageId, required String uid}) async {
    await _chatMessages.doc(messageId).update({'reactions.$uid': FieldValue.delete()});
  }

  static Future<void> adminSetChatMember({required String uid, bool? active, bool? banned, DateTime? restrictedUntil}) async {
    await _chatMembers.doc(uid).set({
      'uid': uid,
      if (active != null) 'active': active,
      if (banned != null) 'banned': banned,
      'restrictedUntil': restrictedUntil == null ? null : Timestamp.fromDate(restrictedUntil),
      'moderatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadChatMembers() async {
    final snap = await _chatMembers.orderBy('name').get();
    return snap.docs;
  }

  static String paymentDocId(String uid) => uid;

  static Future<Map<String, dynamic>?> loadMyMentorship(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  static Future<void> choosePaymentPlan({required String uid, required String plan}) async {
    final normalized = plan == 'installment' ? 'installment' : 'one_time';
    final weekly = normalized == 'installment';
    await _payments.doc(uid).set({
      'uid': uid,
      'plan': normalized,
      'totalAmount': weekly ? 80 : 80,
      'weeklyAmount': weekly ? 20 : 80,
      'weeks': weekly ? 4 : 1,
      'paidWeeks': 0,
      'paymentStatus': 'selected',
      if (weekly) ...{
        'lastInstallmentPaidAt': FieldValue.delete(),
        'nextInstallmentDueAt': FieldValue.delete(),
        'installmentGraceEndsAt': FieldValue.delete(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('users').doc(uid).set({
      'mentorshipPaymentPlan': normalized,
      'mentorshipPaymentStatus': 'selected',
      if (weekly) ...{
        'installmentPaidWeeks': 0,
        'lastInstallmentPaidAt': FieldValue.delete(),
        'installmentNextDueAt': FieldValue.delete(),
        'installmentGraceEndsAt': FieldValue.delete(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> adminRecordInstallmentPayment(String uid) async {
    final paymentRef = _payments.doc(uid);
    final userRef = _db.collection('users').doc(uid);
    final now = DateTime.now();
    await _db.runTransaction<Map<String, dynamic>>((tx) async {
      final paymentSnap = await tx.get(paymentRef);
      final data = paymentSnap.data() ?? <String, dynamic>{};
      final plan = (data['plan'] ?? '').toString();
      if (plan != 'installment') throw StateError('This student is not on the installment plan.');
      final paidWeeks = (data['paidWeeks'] as num?)?.toInt() ?? 0;
      if (paidWeeks >= 4) return {'paidWeeks': 4};
      final newPaidWeeks = paidWeeks + 1;
      final completed = newPaidWeeks >= 4;
      final nextDue = now.add(const Duration(days: 7));
      final graceEnd = now.add(const Duration(days: 8));
      tx.set(paymentRef, {
        'paidWeeks': newPaidWeeks,
        'paymentStatus': completed ? 'completed' : 'current',
        'lastInstallmentPaidAt': Timestamp.fromDate(now),
        if (!completed) 'nextInstallmentDueAt': Timestamp.fromDate(nextDue),
        if (!completed) 'installmentGraceEndsAt': Timestamp.fromDate(graceEnd),
        if (completed) 'nextInstallmentDueAt': FieldValue.delete(),
        if (completed) 'installmentGraceEndsAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(userRef, {
        'installmentPaidWeeks': newPaidWeeks,
        'mentorshipPaymentStatus': completed ? 'completed' : 'current',
        'lastInstallmentPaidAt': Timestamp.fromDate(now),
        if (!completed) 'installmentNextDueAt': Timestamp.fromDate(nextDue),
        if (!completed) 'installmentGraceEndsAt': Timestamp.fromDate(graceEnd),
        if (completed) 'installmentNextDueAt': FieldValue.delete(),
        if (completed) 'installmentGraceEndsAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Each verified installment creates its own secure badge entitlement
      // and Mail item. The student then collects/confirmes the badge from
      // Mail, exactly like the existing badge collection flow.
      final badgeType = 'mentorship_installment_$newPaidWeeks';
      final badgeId = 'mentorship_installment_$newPaidWeeks';
      final entitlementRef = userRef.collection('badgeEntitlements').doc(badgeId);
      final mailRef = userRef.collection('mail').doc();
      tx.set(entitlementRef, {
        'badgeId': badgeId,
        'badgeType': badgeType,
        'eligible': true,
        'status': 'available',
        'studentStage': newPaidWeeks,
        'graduated': completed,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(mailRef, {
        'type': 'badge',
        'title': completed ? 'MENTORSHIP COMPLETED • GRADUATED' : 'MENTORSHIP INSTALLMENT $newPaidWeeks PAID',
        'body': completed
            ? 'Your fourth and final Mentorship installment has been verified. Your Alpha Den profile can now show the black graduation cap and GRADUATED badge. Open this Mail item to collect it.'
            : 'Your Mentorship installment $newPaidWeeks has been verified. Open this Mail item to collect your STUDENT $newPaidWeeks badge for your Alpha Den profile.',
        'badgeIds': [badgeId],
        'badgeType': badgeType,
        'studentStage': newPaidWeeks,
        'graduated': completed,
        'readAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return {'paidWeeks': newPaidWeeks, 'badgeId': badgeId, 'badgeType': badgeType};
    });
    return;
  }

  static Future<String> uploadMentorshipFile({required String category, required String contentId, required String fileName, required List<int> bytes, required String contentType}) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fileRef = await DriveStorageService.uploadBytes(
      bytes: Uint8List.fromList(bytes),
      fileName: '${DateTime.now().millisecondsSinceEpoch}_$safeName',
      contentType: contentType,
      scope: 'mentorship_content:$category:$contentId',
    );
    return 'drive://$fileRef';
  }

  static Future<Uint8List> downloadMentorshipFile(String path) async {
    return DriveStorageService.downloadBytes(path);
  }

  static Future<void> adminSetStudent({required String uid, required bool approved, String? name, String? country, String? timezone}) async {
    final batch = _db.batch();
    final userRef = _db.collection('users').doc(uid);
    batch.set(userRef, {
      'mentorshipApproved': approved,
      'studentApproved': approved,
      'isStudent': approved,
      'studentStatus': approved ? 'Student' : 'Not Student',
      if (approved) 'mentorshipApprovedAt': FieldValue.serverTimestamp(),
      if (!approved) 'mentorshipApprovedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final studentRef = _students.doc(uid);
    batch.set(studentRef, {
      'uid': uid,
      'status': approved ? 'approved' : 'inactive',
      'name': ?name,
      'country': ?country,
      'timezone': ?timezone,
      'updatedAt': FieldValue.serverTimestamp(),
      if (approved) 'approvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> saveLesson({required int number, required String title, required String content, required String videoUrl, required bool published}) async {
    final id = 'session_${number.toString().padLeft(2, '0')}';
    final batch = _db.batch();
    final meta = _lessons.doc(id);
    batch.set(meta, {
      'sessionNumber': number,
      'title': title.trim().isEmpty ? 'Session $number' : title.trim(),
      'isPublished': published,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(meta.collection('protectedContent').doc('details'), {
      'content': content.trim(),
      'videoUrl': videoUrl.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }


  static const List<String> contentCategories = [
    'lectures',
    'assignments',
    'backtesting',
    'paper_money',
  ];

  static String contentDocId(String category, int number) => 'content_${category}_${number.toString().padLeft(2, '0')}';

  static Future<void> saveCategoryContent({
    required String category,
    required int number,
    required String title,
    required String notes,
    required String videoUrl,
    required bool published,
    List<Map<String, dynamic>> pdfFiles = const [],
    List<Map<String, dynamic>> imageFiles = const [],
  }) async {
    final id = contentDocId(category, number);
    final ref = _lessons.doc(id);
    final batch = _db.batch();
    batch.set(ref, {
      'contentCategory': category,
      'contentNumber': number,
      'sessionNumber': number,
      'title': title.trim().isEmpty ? '${category.replaceAll('_', ' ').toUpperCase()} $number' : title.trim(),
      'isPublished': published,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(ref.collection('protectedContent').doc('details'), {
      'notes': notes.trim(),
      'content': notes.trim(),
      'videoUrl': videoUrl.trim(),
      'pdfFiles': pdfFiles,
      'imageFiles': imageFiles,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadCategoryContent(String category) async {
    final snap = await _lessons.where('contentCategory', isEqualTo: category).get();
    final docs = [...snap.docs];
    docs.sort((a, b) => ((a.data()['contentNumber'] as num?)?.toInt() ?? 0).compareTo((b.data()['contentNumber'] as num?)?.toInt() ?? 0));
    return docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadLessons() async {
    final snap = await _lessons.orderBy('sessionNumber').get();
    return snap.docs;
  }

  static Future<Map<String, dynamic>?> loadLessonContent(String lessonId) async {
    final snap = await _lessons.doc(lessonId).collection('protectedContent').doc('details').get();
    return snap.data();
  }

  static Future<void> saveSchedule({required String id, required String studentUid, required String studentName, required String country, required String timezone, required DateTime classDateTime, required String details, required String meetUrl}) async {
    final ref = id.trim().isEmpty ? _schedules.doc() : _schedules.doc(id);
    await ref.set({
      'id': ref.id,
      'studentUid': studentUid,
      'studentName': studentName.trim(),
      'country': country.trim(),
      'timezone': timezone.trim(),
      'scheduledAt': Timestamp.fromDate(classDateTime),
      'details': details.trim(),
      'meetUrl': meetUrl.trim(),
      'status': 'scheduled',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _reminders.doc(ref.id).set({
      'scheduleId': ref.id,
      'studentUid': studentUid,
      'studentName': studentName.trim(),
      'scheduledAt': Timestamp.fromDate(classDateTime),
      'title': 'Mentorship Class Reminder',
      'body': '${studentName.trim()} has a live class scheduled.',
      'status': 'scheduled',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteSchedule(String id) async {
    await _schedules.doc(id).delete();
    await _reminders.doc(id).delete();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadSchedules({String? studentUid}) async {
    Query<Map<String, dynamic>> query = _schedules.orderBy('scheduledAt');
    if (studentUid != null && studentUid.trim().isNotEmpty) query = query.where('studentUid', isEqualTo: studentUid);
    final snap = await query.get();
    return snap.docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadStudents() async {
    final snap = await _students.orderBy('updatedAt', descending: true).get();
    return snap.docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadStudentDirectory() async {
    final snap = await _studentDirectory.get();
    final docs = [...snap.docs];
    docs.sort((a, b) => a.id.compareTo(b.id));
    return docs;
  }

  static Future<void> saveStudentDirectoryEntry({
    required int slot,
    required String studentUid,
    required String studentName,
    required String age,
    required String country,
  }) async {
    if (slot < 1 || slot > 25) throw ArgumentError('Student slot must be between 1 and 25.');
    final normalizedUid = studentUid.trim();
    final normalizedName = studentName.trim();
    final normalizedAge = age.trim();
    final normalizedCountry = country.trim();
    if (normalizedUid.isEmpty || normalizedName.isEmpty || normalizedAge.isEmpty || normalizedCountry.isEmpty) {
      throw ArgumentError('UID, name, age and country are required.');
    }
    final id = 'student_${slot.toString().padLeft(2, '0')}';
    await _studentDirectory.doc(id).set({
      'slot': slot,
      'studentUid': normalizedUid,
      'studentName': normalizedName,
      'age': normalizedAge,
      'country': normalizedCountry,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> markReminderDue(String id) async {
    await _reminders.doc(id).set({'status': 'due', 'dueAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  static User? get currentUser => FirebaseAuth.instance.currentUser;
}
