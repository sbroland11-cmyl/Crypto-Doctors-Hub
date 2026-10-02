import 'package:cloud_firestore/cloud_firestore.dart';

class FeedPostModel {
  final String id;
  final String authorUid;
  final String authorDisplayName;
  final String authorPhotoUrl;
  final String? authorPhotoBase64;
  final String badge;
  final int referralsCount;
  final bool verified;
  final String text;
  final bool bullish;
  final List<String> hashtags;
  final List<String> coins;
  final String? signalAsset;
  final String? signalEntry;
  final bool? signalLongDirection;
  final int? signalLeverage;
  final String? signalTp1;
  final String? signalTp2;
  final String? signalTp3;
  final String? signalStopLoss;
  final String? imageBase64;
  final String? articleTitle;
  final String? articleBody;
  final String? articleThumbnailBase64;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final bool tp1Hit;
  final bool tp2Hit;
  final bool tp3Hit;
  final bool stopLossHit;
  final bool breakEven;
  final bool winTradeCounted;
  final String? tp1Profit;
  final String? tp2Profit;
  final String? tp3Profit;
  final String? stopLossProfit;
  final String? breakEvenProfit;
  final String? winResultImageBase64;
  final int winTrades;
  final int repostsCount;
  final int followersCount;
  final int viewsCount;
  final String sourceType;
  final String? sourceId;
  final bool isPublished;

  const FeedPostModel({
    required this.id,
    required this.authorUid,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.authorPhotoBase64,
    required this.badge,
    required this.referralsCount,
    required this.verified,
    required this.text,
    required this.bullish,
    required this.hashtags,
    required this.coins,
    required this.signalAsset,
    required this.signalEntry,
    required this.signalLongDirection,
    required this.signalLeverage,
    required this.signalTp1,
    required this.signalTp2,
    required this.signalTp3,
    required this.signalStopLoss,
    required this.imageBase64,
    required this.articleTitle,
    required this.articleBody,
    required this.articleThumbnailBase64,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.tp1Hit,
    required this.tp2Hit,
    required this.tp3Hit,
    required this.stopLossHit,
    required this.breakEven,
    required this.winTradeCounted,
    required this.tp1Profit,
    required this.tp2Profit,
    required this.tp3Profit,
    required this.stopLossProfit,
    required this.breakEvenProfit,
    required this.winResultImageBase64,
    required this.winTrades,
    required this.repostsCount,
    required this.followersCount,
    required this.viewsCount,
    required this.sourceType,
    required this.sourceId,
    required this.isPublished,
  });

  static DateTime _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  static List<String> _strings(dynamic value) {
    if (value is Iterable) return value.map((e) => e.toString()).toList();
    return const <String>[];
  }

  static int _int(dynamic value) => (value as num?)?.toInt() ?? 0;

  factory FeedPostModel.fromData(String id, Map<String, dynamic> data) {
    return FeedPostModel(
      id: id,
      authorUid: (data['authorUid'] ?? '').toString(),
      authorDisplayName: (data['authorDisplayName'] ?? data['author'] ?? '').toString(),
      authorPhotoUrl: (data['authorPhotoUrl'] ?? '').toString(),
      authorPhotoBase64: (data['authorPhotoBase64'] ?? data['profilePicBase64'])?.toString(),
      badge: (data['badge'] ?? 'BRONZE').toString(),
      referralsCount: _int(data['referralsCount'] ?? data['referrals']),
      verified: data['verified'] == true || data['verifiedCreatorApproved'] == true,
      text: (data['text'] ?? '').toString(),
      bullish: data['bullish'] != false,
      hashtags: _strings(data['hashtags']),
      coins: _strings(data['coins']),
      signalAsset: data['signalAsset']?.toString(),
      signalEntry: data['signalEntry']?.toString(),
      signalLongDirection: data['signalLongDirection'] is bool ? data['signalLongDirection'] as bool : null,
      signalLeverage: data['signalLeverage'] == null ? null : _int(data['signalLeverage']),
      signalTp1: data['signalTp1']?.toString(),
      signalTp2: data['signalTp2']?.toString(),
      signalTp3: data['signalTp3']?.toString(),
      signalStopLoss: data['signalStopLoss']?.toString(),
      imageBase64: data['imageBase64']?.toString(),
      articleTitle: data['articleTitle']?.toString(),
      articleBody: data['articleBody']?.toString(),
      articleThumbnailBase64: data['articleThumbnailBase64']?.toString(),
      createdAt: _date(data['createdAt']),
      likesCount: _int(data['likesCount'] ?? data['likes']),
      commentsCount: _int(data['commentsCount'] ?? data['comments']),
      tp1Hit: data['tp1Hit'] == true,
      tp2Hit: data['tp2Hit'] == true,
      tp3Hit: data['tp3Hit'] == true,
      stopLossHit: data['stopLossHit'] == true,
      breakEven: data['breakEven'] == true,
      winTradeCounted: data['winTradeCounted'] == true,
      tp1Profit: data['tp1Profit']?.toString(),
      tp2Profit: data['tp2Profit']?.toString(),
      tp3Profit: data['tp3Profit']?.toString(),
      stopLossProfit: data['stopLossProfit']?.toString(),
      breakEvenProfit: data['breakEvenProfit']?.toString(),
      winResultImageBase64: data['winResultImageBase64']?.toString(),
      winTrades: _int(data['winTrades']),
      repostsCount: _int(data['repostsCount']),
      followersCount: _int(data['followersCount']),
      viewsCount: _int(data['viewsCount']),
      sourceType: (data['sourceType'] ?? 'feed').toString(),
      sourceId: data['sourceId']?.toString(),
      isPublished: data['isPublished'] != false,
    );
  }

  Map<String, dynamic> toData() => <String, dynamic>{
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'authorPhotoUrl': authorPhotoUrl,
    if (authorPhotoBase64 != null) 'authorPhotoBase64': authorPhotoBase64,
    'badge': badge,
    'referralsCount': referralsCount,
    'verified': verified,
    'text': text,
    'bullish': bullish,
    'hashtags': hashtags,
    'coins': coins,
    'signalAsset': signalAsset,
    'signalEntry': signalEntry,
    'signalLongDirection': signalLongDirection,
    'signalLeverage': signalLeverage,
    'signalTp1': signalTp1,
    'signalTp2': signalTp2,
    'signalTp3': signalTp3,
    'signalStopLoss': signalStopLoss,
    'imageBase64': imageBase64,
    'articleTitle': articleTitle,
    'articleBody': articleBody,
    'articleThumbnailBase64': articleThumbnailBase64,
    'createdAt': Timestamp.fromDate(createdAt),
    'likesCount': likesCount,
    'commentsCount': commentsCount,
    'tp1Hit': tp1Hit,
    'tp2Hit': tp2Hit,
    'tp3Hit': tp3Hit,
    'stopLossHit': stopLossHit,
    'breakEven': breakEven,
    'winTradeCounted': winTradeCounted,
    'tp1Profit': tp1Profit,
    'tp2Profit': tp2Profit,
    'tp3Profit': tp3Profit,
    'stopLossProfit': stopLossProfit,
    'breakEvenProfit': breakEvenProfit,
    'winResultImageBase64': winResultImageBase64,
    'winTrades': winTrades,
    'repostsCount': repostsCount,
    'followersCount': followersCount,
    'viewsCount': viewsCount,
    'sourceType': sourceType,
    'sourceId': sourceId,
    'isPublished': isPublished,
  };
}
