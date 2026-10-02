import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feed_post_model.dart';

class FeedService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _posts => _db.collection('feed_posts');

  static Future<String> createPost(FeedPostModel post) async {
    final ref = post.id.trim().isEmpty ? _posts.doc() : _posts.doc(post.id);
    await ref.set(post.toData());
    return ref.id;
  }

  static Future<List<FeedPostModel>> loadFeed({int limit = 100}) async {
    final snap = await _posts.where('isPublished', isEqualTo: true).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => FeedPostModel.fromData(d.id, d.data())).toList();
  }

  static Future<void> updatePost(String postId, {required String authorUid, required String text}) async {
    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists || (snap.data()?['authorUid'] ?? '') != authorUid) throw StateError('Not the post author.');
    await ref.update({'text': text, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> deletePost(
    String postId, {
    required String authorUid,
    String? requesterUid,
    bool adminDelete = false,
  }) async {
    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('Post not found.');
    final data = snap.data() ?? <String, dynamic>{};
    final sourceType = (data['sourceType'] ?? '').toString();
    final isAlphaDenPost = sourceType == 'alpha_den' || sourceType == 'alpha_den_signal';
    final requesterIsOwner = (requesterUid ?? authorUid) == authorUid;
    if (!requesterIsOwner && !adminDelete) {
      throw StateError('Not authorized to delete this post.');
    }
    if (adminDelete) {
      if (sourceType == 'analysis') {
        final sourceId = (data['sourceId'] ?? '').toString();
        if (sourceId.isNotEmpty) {
          await _db.collection('analysis_posts').doc(sourceId).delete();
        }
      } else if (sourceType == 'live_call') {
        final sourceId = (data['sourceId'] ?? '').toString();
        if (sourceId.isNotEmpty) {
          await _db.collection('live_calls').doc(sourceId).delete();
        }
      }
    }
    await ref.delete();
  }

  static Future<List<Map<String, dynamic>>> loadComments(String postId) async {
    final snap = await _posts.doc(postId).collection('comments').orderBy('createdAt').get();
    return snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
  }

  static String newCommentId(String postId) => _posts.doc(postId).collection('comments').doc().id;

  static Future<String> addComment({required String postId, required String authorUid, required String author, required String text, String? parentId, bool creatorReply = false, String? commentId}) async {
    final ref = commentId == null ? _posts.doc(postId).collection('comments').doc() : _posts.doc(postId).collection('comments').doc(commentId);
    await ref.set(<String, dynamic>{
      'authorUid': authorUid, 'author': author, 'text': text,
      'parentId': parentId, 'creatorReply': creatorReply,
      'likes': 0, 'createdAt': FieldValue.serverTimestamp(),
    });
    // The comment document is the authoritative write. Keep the count update
    // independent so a slow secondary write never delays comment rendering.
    _posts.doc(postId).update({'commentsCount': FieldValue.increment(1)}).catchError((_) {});
    return ref.id;
  }

  static Future<void> toggleCommentLike({required String postId, required String commentId, required String uid, required bool liked}) async {
    final ref = _posts.doc(postId).collection('comments').doc(commentId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final current = (snap.data()?['likes'] as num?)?.toInt() ?? 0;
      tx.update(ref, {'likes': (current + (liked ? 1 : -1)).clamp(0, 1000000)});
    });
  }

  static Future<String> reportPost({required String postId, required String reporterUid, required String reason, String details = ''}) async {
    final ref = await _db.collection('content_reports').add({'type': 'post', 'postId': postId, 'reporterUid': reporterUid, 'reason': reason, 'details': details, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  static Future<String> reportComment({required String postId, required String commentId, required String reporterUid, required String reason, String details = ''}) async {
    final ref = await _db.collection('content_reports').add({'type': 'comment', 'postId': postId, 'commentId': commentId, 'reporterUid': reporterUid, 'reason': reason, 'details': details, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }
}
