import 'package:cloud_firestore/cloud_firestore.dart';

class AlphaDenService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Alpha Den profile data is stored inside the user's own users/{uid}
  // document. The existing user security rules already allow the owner to
  // read/update this document, so profile persistence does not depend on a
  // separate Alpha Den ruleset.
  static Future<bool> hasProfile(String uid) async {
    final profile = await loadProfile(uid);
    return profile != null;
  }

  static Future<Map<String, dynamic>?> loadProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    final raw = data?['alphaDenProfile'];
    if (raw is Map) {
      final profile = Map<String, dynamic>.from(raw);
      // Entitlements live on the root user document so approval is controlled
      // by the account/backend state, while the Alpha Den card can display
      // the current approved badges on both private and public profiles.
      profile['isPremium'] = data?['isPremium'] == true;
      profile['mentorshipApproved'] = data?['mentorshipApproved'] == true || data?['isMentorship'] == true || data?['mentorship'] == true || data?['studentApproved'] == true || data?['isStudent'] == true;
      return profile;
    }
    return null;
  }

  static Stream<Map<String, dynamic>?> watchProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final raw = doc.data()?['alphaDenProfile'];
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    });
  }

  // Alpha Den posts use the same published feed_posts collection as the CD
  // Feed. This gives us one persistent source of truth and avoids a second
  // collection/ruleset. We filter the user's Alpha Den posts in Dart.
  static Future<List<Map<String, dynamic>>> loadPosts(String uid) async {
    final snapshot = await _db
        .collection('feed_posts')
        .where('isPublished', isEqualTo: true)
        .limit(500)
        .get();

    final posts = snapshot.docs
        .where((doc) {
          final data = doc.data();
          final sourceType = (data['sourceType'] ?? '').toString();
          return data['authorUid'] == uid && (sourceType == 'alpha_den' || sourceType == 'article');
        })
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();

    posts.sort((a, b) {
      final at = a['createdAt'];
      final bt = b['createdAt'];
      final ad = at is Timestamp ? at.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final bd = bt is Timestamp ? bt.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return posts;
  }

  static Future<void> saveProfile({
    required String uid,
    required String username,
    required String handle,
    required String name,
    required String age,
    required String sex,
    required String bio,
    required String profilePicUrl,
    required int followers,
    required int posts,
    required int likes,
    required int views,
    int reposts = 0,
    required int referrals,
    int winTrades = 0,
    required bool verified,
    String? profilePicBase64,
    DateTime? profilePicChangedAt,
    DateTime? nicknameChangedAt,
    DateTime? bioChangedAt,
    DateTime? sexChangedAt,
    DateTime? ageSetAt,
  }) async {
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'alphaDenProfile': {
        'uid': uid,
        'username': username,
        'handle': handle,
        'name': name,
        'age': age,
        'sex': sex,
        'bio': bio,
        'profilePicUrl': profilePicUrl,
        if (profilePicBase64 != null && profilePicBase64.isNotEmpty) 'profilePicBase64': profilePicBase64,
        if (profilePicChangedAt != null) 'profilePicChangedAt': Timestamp.fromDate(profilePicChangedAt),
        if (nicknameChangedAt != null) 'nicknameChangedAt': Timestamp.fromDate(nicknameChangedAt),
        if (bioChangedAt != null) 'bioChangedAt': Timestamp.fromDate(bioChangedAt),
        if (sexChangedAt != null) 'sexChangedAt': Timestamp.fromDate(sexChangedAt),
        if (ageSetAt != null) 'ageSetAt': Timestamp.fromDate(ageSetAt),
        'followers': followers,
        'posts': posts,
        'likes': likes,
        'views': views,
        'reposts': reposts,
        'referrals': referrals,
        'winTrades': winTrades,
        'verifiedCreatorApproved': verified,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  static Future<void> syncPublicProfileToPosts({
    required String uid,
    required String username,
    required String profilePicUrl,
    required String? profilePicBase64,
    required int referrals,
    int winTrades = 0,
    required bool verified,
  }) async {
    final snapshot = await _db.collection('feed_posts').where('authorUid', isEqualTo: uid).limit(500).get();
    if (snapshot.docs.isEmpty) return;
    WriteBatch batch = _db.batch();
    var count = 0;
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'authorDisplayName': username,
        'authorPhotoUrl': profilePicUrl,
        'profilePicBase64': profilePicBase64,
        'badge': referrals >= 100 ? 'PLATINUM' : referrals >= 25 ? 'GOLD' : referrals >= 5 ? 'SILVER' : 'BRONZE',
        'referralsCount': referrals,
        'verified': verified,
        'winTrades': winTrades,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count == 450) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  // Kept as a compatibility guard for the Alpha Den creation flow. The
  // actual persistent post is created by FeedService through the shared feed.
  static CollectionReference<Map<String, dynamic>> _myRepostsRef(String uid) =>
      _db.collection('users').doc(uid).collection('alphaDenReposts');

  static CollectionReference<Map<String, dynamic>> _postRepostsRef(String postId) =>
      _db.collection('feed_posts').doc(postId).collection('reposts');

  static Future<List<Map<String, dynamic>>> loadMyReposts(String uid) async {
    final snapshot = await _myRepostsRef(uid).orderBy('createdAt', descending: true).limit(500).get();
    return snapshot.docs.map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()}).toList();
  }

  static Future<List<Map<String, dynamic>>> loadPublicReposts(String uid) async {
    // Public Alpha Den profiles intentionally expose the user's repost tab.
    // Firestore rules separately allow signed-in users to read this public
    // subcollection while only the owner can create/delete reposts.
    final snapshot = await _myRepostsRef(uid).orderBy('createdAt', descending: true).limit(500).get();
    return snapshot.docs.map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()}).toList();
  }

  static Future<bool> hasMyRepost({required String uid, required String postId}) async {
    final doc = await _myRepostsRef(uid).doc(postId).get();
    return doc.exists;
  }

  static Future<int> repostCount(String postId) async {
    final snapshot = await _postRepostsRef(postId).limit(500).get();
    return snapshot.docs.length;
  }

  static Future<void> createRepost({
    required String uid,
    required String postId,
    required Map<String, dynamic> snapshot,
  }) async {
    final myRef = _myRepostsRef(uid).doc(postId);
    final postRef = _db.collection('feed_posts').doc(postId);
    final repostRef = _postRepostsRef(postId).doc(uid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(repostRef);
      if (existing.exists) return;
      final parent = await tx.get(postRef);
      final currentCount = (parent.data()?['repostsCount'] as num?)?.toInt() ?? 0;
      final data = <String, dynamic>{
        ...snapshot,
        'originalPostId': postId,
        'reposterUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      };
      tx.set(myRef, data, SetOptions(merge: true));
      tx.set(repostRef, {
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(postRef, {'repostsCount': currentCount + 1});
    });
  }

  static Future<void> deleteRepost({required String uid, required String postId}) async {
    final myRef = _myRepostsRef(uid).doc(postId);
    final postRef = _db.collection('feed_posts').doc(postId);
    final repostRef = _postRepostsRef(postId).doc(uid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(repostRef);
      if (!existing.exists) {
        tx.delete(myRef);
        return;
      }
      final parent = await tx.get(postRef);
      final currentCount = (parent.data()?['repostsCount'] as num?)?.toInt() ?? 0;
      tx.delete(myRef);
      tx.delete(repostRef);
      tx.update(postRef, {'repostsCount': currentCount > 0 ? currentCount - 1 : 0});
    });
  }

  static Future<Map<String, dynamic>> updateSignalOutcome({
    required String uid,
    required String postId,
    required Map<String, dynamic> outcome,
  }) async {
    final postRef = _db.collection('feed_posts').doc(postId);
    final userRef = _db.collection('users').doc(uid);
    var counted = false;
    await _db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) throw StateError('Signal post not found.');
      final postData = postSnap.data() ?? <String, dynamic>{};
      final merged = <String, dynamic>{...outcome};
      final completeWin = merged['tp1Hit'] == true && merged['tp2Hit'] == true && merged['tp3Hit'] == true;
      final alreadyCounted = postData['winTradeCounted'] == true;
      if (completeWin && !alreadyCounted) {
        merged['winTradeCounted'] = true;
        counted = true;
        final userSnap = await tx.get(userRef);
        final data = userSnap.data() ?? <String, dynamic>{};
        final profileRaw = data['alphaDenProfile'];
        final profile = profileRaw is Map ? Map<String, dynamic>.from(profileRaw) : <String, dynamic>{};
        final currentWins = (profile['winTrades'] as num?)?.toInt() ?? 0;
        profile['winTrades'] = currentWins + 1;
        profile['updatedAt'] = FieldValue.serverTimestamp();
        tx.set(userRef, {'alphaDenProfile': profile, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } else if (alreadyCounted) {
        merged['winTradeCounted'] = true;
      }
      tx.update(postRef, merged);
    });
    return {'counted': counted};
  }

  static Future<void> incrementWinTrade(String uid) async {
    final ref = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final raw = data['alphaDenProfile'];
      final profile = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      profile['winTrades'] = ((profile['winTrades'] as num?)?.toInt() ?? 0) + 1;
      profile['updatedAt'] = FieldValue.serverTimestamp();
      tx.set(ref, {'alphaDenProfile': profile, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  static Future<void> createPost({
    required String uid,
    required String text,
    required bool bullish,
    required bool isSignal,
    String? signalAsset,
    String? signalEntry,
    bool? signalLongDirection,
    int? signalLeverage,
    String? signalTp1,
    String? signalTp2,
    String? signalTp3,
    String? signalStopLoss,
    List<String> hashtags = const [],
    List<String> coins = const [],
  }) async {
    if (!await hasProfile(uid)) {
      throw StateError('Create an Alpha Den profile before posting.');
    }
  }
}
