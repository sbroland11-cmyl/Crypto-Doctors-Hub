import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> publish({
    required String uid,
    required String title,
    required String body,
    String type = 'general',
  }) async {
    final batch = _db.batch();
    final mailRef = _db.collection('users').doc(uid).collection('mail').doc();
    batch.set(mailRef, {
      'title': title,
      'message': body,
      'body': body,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'readAt': null,
    });
    final notificationRef = _db.collection('users').doc(uid).collection('notifications').doc();
    batch.set(notificationRef, {
      'title': title,
      'body': body,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    // A trusted backend/trigger consumes this event and sends the same event
    // through email and FCM push. The Flutter client never sends email or FCM
    // credentials itself.
    final eventRef = _db.collection('notification_events').doc();
    batch.set(eventRef, {
      'uid': uid,
      'title': title,
      'body': body,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
    await batch.commit();
  }
}
