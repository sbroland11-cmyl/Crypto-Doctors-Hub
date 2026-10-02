import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class CustomerSupportService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('customer_support_requests');

  static Future<String> createRequest({
    required String uid,
    required String email,
    required String category,
    required String details,
    required String status,
    required String action,
    String userName = '',
  }) async {
    final ref = _requests.doc();
    await ref.set(<String, dynamic>{
      'ticketId': ref.id,
      'uid': uid,
      'userName': userName,
      'email': email,
      'category': category,
      'details': details,
      'status': status,
      'action': action,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String generateTicketCode() {
    final now = DateTime.now();
    final suffix = List.generate(6, (_) => math.Random().nextInt(36).toRadixString(36)).join().toUpperCase();
    return 'CDH-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$suffix';
  }

  static Future<String> createTicket({
    required String uid,
    required String userName,
    required String email,
    required String details,
  }) async {
    final ref = _requests.doc();
    final ticketCode = generateTicketCode();
    await ref.set(<String, dynamic>{
      'ticketId': ticketCode,
      'uid': uid,
      'userName': userName,
      'email': email,
      'category': 'Submit a Ticket',
      'details': details,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ticketCode;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> userTickets(String uid) =>
      _requests.where('uid', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> allTickets() =>
      _requests.where('category', isEqualTo: 'Submit a Ticket').orderBy('createdAt', descending: true).limit(100).snapshots();

  static CollectionReference<Map<String, dynamic>> ticketMessages(String ticketDocId) =>
      _requests.doc(ticketDocId).collection('messages');

  static Future<void> sendTicketMessage({
    required String ticketDocId,
    required String senderUid,
    required String senderName,
    required String senderRole,
    required String text,
  }) async {
    final message = text.trim();
    if (message.isEmpty) return;
    await ticketMessages(ticketDocId).add(<String, dynamic>{
      'senderUid': senderUid,
      'senderName': senderName,
      'senderRole': senderRole,
      'text': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _requests.doc(ticketDocId).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'status': senderRole == 'admin' ? 'awaiting_user' : 'open',
    });
    if (senderRole == 'admin') {
      final ticket = await _requests.doc(ticketDocId).get();
      final data = ticket.data() ?? <String, dynamic>{};
      final uid = (data['uid'] ?? '').toString();
      if (uid.isNotEmpty) {
        try {
          await NotificationService.publish(uid: uid, title: 'Support Ticket Update', body: message, type: 'support_ticket');
        } catch (_) {}
      }
    }
  }

  static Future<void> updateTicketStatus(String ticketDocId, String status) =>
      _requests.doc(ticketDocId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // This document is consumed by the project's configured email backend/trigger.
  static Future<void> queueReportEmail({
    required String reportId,
    required String email,
    required String uid,
  }) async {
    await _db.collection('report_email_notifications').doc(reportId).set({
      'reportId': reportId,
      'uid': uid,
      'email': email,
      'subject': 'Crypto Doctors Hub — Report Received',
      'message': 'Your report has been received. Please wait up to 24 hours for the result.',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
  }
}
