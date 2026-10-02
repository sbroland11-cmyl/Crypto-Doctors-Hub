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
    // Keep the parent post count in sync with the authoritative comment write.
    // The Firestore rules permit this as a single-field +/-1 update.
    await _posts.doc(postId).update({'commentsCount': FieldValue.increment(1)});
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


  static Stream<List<FeedPostModel>> watchFeed({int limit = 100}) {
    return _posts
        .where('isPublished', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FeedPostModel.fromData(doc.id, doc.data()))
            .toList());
  }

  static CollectionReference<Map<String, dynamic>> _engagementRef(
    String postId,
    String kind,
  ) => _posts.doc(postId).collection(kind);

  static Future<bool> hasPostLike({required String postId, required String uid}) async {
    return (await _engagementRef(postId, 'likes').doc(uid).get()).exists;
  }

  static Future<bool> hasPostRepost({required String postId, required String uid}) async {
    return (await _engagementRef(postId, 'reposts').doc(uid).get()).exists;
  }

  static Future<bool> hasPostLikeBySourceId({required String sourceId, required String uid}) async {
    final postId = await findPostIdBySourceId(sourceId);
    return postId == null ? false : hasPostLike(postId: postId, uid: uid);
  }

  static Future<void> togglePostLike({required String postId, required String uid, required bool liked}) async {
    final postRef = _posts.doc(postId);
    final engagementRef = _engagementRef(postId, 'likes').doc(uid);
    await _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) return;
      final data = postSnap.data() ?? <String, dynamic>{};
      final current = ((data['likesCount'] ?? data['likes']) as num?)?.toInt() ?? 0;
      final likeSnap = await tx.get(engagementRef);
      final alreadyLiked = likeSnap.exists;
      if (liked && !alreadyLiked) {
        tx.set(engagementRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(postRef, {'likesCount': current + 1, 'likes': current + 1});
      } else if (!liked && alreadyLiked) {
        tx.delete(engagementRef);
        tx.update(postRef, {'likesCount': (current - 1).clamp(0, 1000000), 'likes': (current - 1).clamp(0, 1000000)});
      }
    });
  }

  static Future<void> togglePostLikeBySourceId({required String sourceId, required String uid, required bool liked}) async {
    final postId = await findPostIdBySourceId(sourceId);
    if (postId == null) return;
    await togglePostLike(postId: postId, uid: uid, liked: liked);
  }

  static Future<void> togglePostRepost({required String postId, required String uid, required bool reposted}) async {
    final postRef = _posts.doc(postId);
    final engagementRef = _engagementRef(postId, 'reposts').doc(uid);
    await _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) return;
      final current = (postSnap.data()?['repostsCount'] ?? postSnap.data()?['reposts']) is num
          ? ((postSnap.data()?['repostsCount'] ?? postSnap.data()?['reposts']) as num).toInt()
          : 0;
      final repostSnap = await tx.get(engagementRef);
      final alreadyReposted = repostSnap.exists;
      if (reposted && !alreadyReposted) {
        tx.set(engagementRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(postRef, {'repostsCount': current + 1, 'reposts': current + 1});
      } else if (!reposted && alreadyReposted) {
        tx.delete(engagementRef);
        tx.update(postRef, {'repostsCount': (current - 1).clamp(0, 1000000), 'reposts': (current - 1).clamp(0, 1000000)});
      }
    });
  }

  static Future<void> togglePostRepostBySourceId({required String sourceId, required String uid, required bool reposted}) async {
    final postId = await findPostIdBySourceId(sourceId);
    if (postId == null) return;
    await togglePostRepost(postId: postId, uid: uid, reposted: reposted);
  }

  static Future<String?> findPostIdBySourceId(String sourceId) async {
    final value = sourceId.trim();
    if (value.isEmpty) return null;
    final snap = await _posts.where('sourceId', isEqualTo: value).limit(1).get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  static Future<void> recordShare({required String postId, required String uid}) async {
    final postRef = _posts.doc(postId);
    final shareRef = _engagementRef(postId, 'shares').doc(uid);
    await _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) return;
      final shareSnap = await tx.get(shareRef);
      if (shareSnap.exists) return;
      final current = (postSnap.data()?['sharesCount'] ?? postSnap.data()?['shares']) is num
          ? ((postSnap.data()?['sharesCount'] ?? postSnap.data()?['shares']) as num).toInt()
          : 0;
      tx.set(shareRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.update(postRef, {'sharesCount': current + 1, 'shares': current + 1});
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
