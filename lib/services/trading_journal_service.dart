import 'package:cloud_firestore/cloud_firestore.dart';
import 'drive_storage_service.dart';

class TradingJournalService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;


  static Future<void> _archive(String scope, String recordId, String uid, Map<String, dynamic> data) async {
    try { await DriveStorageService.archiveJsonRecord(scope: scope, recordId: recordId, ownerUid: uid, data: data); } catch (_) {}
  }

  static DateTime _startOfDay([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _startOfWeek([DateTime? now]) {
    final n = now ?? DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime _startOfMonth([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month);
  }

  static DateTime _startOfYear([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year);
  }

  static DateTime _endOf(DateTime start, String period) {
    if (period == 'daily') return start.add(const Duration(days: 1));
    if (period == 'weekly') return start.add(const Duration(days: 7));
    if (period == 'monthly') return DateTime(start.year, start.month + 1);
    return DateTime(start.year + 1);
  }

  static String _periodKey(String period, DateTime date) {
    if (period == 'daily') {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (period == 'weekly') {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (period == 'monthly') {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
    return '${date.year}';
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _closedCalls(DateTime start, DateTime end) async {
    // Read only published Live Calls first so the query remains compatible
    // with the current Firestore security rule. Date filtering is applied
    // locally to avoid requiring a new composite index.
    final snap = await _db
        .collection('live_calls')
        .where('isPublished', isEqualTo: true)
        .limit(500)
        .get();
    return snap.docs.where((d) {
      final data = d.data();
      if (data['tradeClosed'] != true) return false;
      final raw = data['closedAt'];
      final closedAt = raw is Timestamp ? raw.toDate() : DateTime.tryParse((raw ?? '').toString());
      return closedAt != null && !closedAt.isBefore(start) && closedAt.isBefore(end);
    }).toList();
  }

  static double _percent(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('%', '').replaceAll('+', '').trim();
    return double.tryParse(raw) ?? 0;
  }

  static Future<Map<String, double>> loadCommunityPerformance() async {
    final now = DateTime.now();
    final week = _startOfWeek(now);
    final keys = <String, String>{
      'daily': _periodKey('daily', now),
      'weekly': _periodKey('weekly', week),
      'monthly': _periodKey('monthly', now),
      'yearly': _periodKey('yearly', now),
    };
    final result = <String, double>{};
    for (final e in keys.entries) {
      final d = await _db.collection('journalCommunityAggregates').doc('${e.key}_${e.value}').get();
      final data = d.data();
      if (data != null && (data['closedTradeCount'] as num?)?.toInt() != null && (data['closedTradeCount'] as num).toInt() > 0) {
        final count = (data['closedTradeCount'] as num).toDouble();
        result[e.key] = ((data['sumProfitPercentage'] as num?)?.toDouble() ?? 0) / count;
      } else {
        final start = e.key == 'daily' ? _startOfDay(now) : e.key == 'weekly' ? week : e.key == 'monthly' ? _startOfMonth(now) : _startOfYear(now);
        final docs = await _closedCalls(start, _endOf(start, e.key));
        final values = docs.map((d) => (d.data()['finalProfitPercentage'] as num?)?.toDouble() ?? _percent(d.data()['resultPercentage'])).toList();
        result[e.key] = values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
      }
    }
    return result;
  }

  static Future<Map<String, double>> loadPersonalPerformance(String uid) async {
    final now = DateTime.now();
    final week = _startOfWeek(now);
    final keys = <String, String>{
      'daily': _periodKey('daily', now),
      'weekly': _periodKey('weekly', week),
      'monthly': _periodKey('monthly', now),
      'yearly': _periodKey('yearly', now),
    };
    final result = <String, double>{};

    // These tiles represent the user's community/live-call performance: only
    // officially closed Live Calls that this user marked as a participated
    // trade are included. Private manual-profit entries and Trading Task
    // results are intentionally kept out of these community-performance tiles.
    final journal = await _db
        .collection('users')
        .doc(uid)
        .collection('tradingJournal')
        .where('status', isEqualTo: 'CLOSED')
        .get();

    for (final e in keys.entries) {
      final start = e.key == 'daily'
          ? _startOfDay(now)
          : e.key == 'weekly'
              ? week
              : e.key == 'monthly'
                  ? _startOfMonth(now)
                  : _startOfYear(now);
      final end = _endOf(start, e.key);

      double sum = 0;
      double count = 0;

      final aggregate = await _db
          .collection('users')
          .doc(uid)
          .collection('journalAggregates')
          .doc('${e.key}_${e.value}')
          .get();
      final data = aggregate.data();

      if (data != null && (data['closedTradeCount'] as num?)?.toDouble() != null) {
        sum = (data['sumProfitPercentage'] as num?)?.toDouble() ?? 0;
        count = (data['closedTradeCount'] as num?)?.toDouble() ?? 0;
      } else {
        for (final d in journal.docs) {
          final x = d.data();
          if (x['interaction'] != 'like') continue;
          final closedAt = x['closedAt'];
          final date = closedAt is Timestamp
              ? closedAt.toDate()
              : DateTime.tryParse((x['closedAt'] ?? '').toString());
          if (date != null && !date.isBefore(start) && date.isBefore(end)) {
            sum += (x['finalProfitPercentage'] as num?)?.toDouble() ??
                _percent(x['resultPercentage']);
            count += 1;
          }
        }
      }

      result[e.key] = count == 0 ? 0 : sum / count;
    }
    return result;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> closedLiveCallsStream(String period) {
    // Keep the query provably readable under the published Live Call rule.
    // Period/tradeClosed filtering is applied locally by the history page.
    return _db.collection('live_calls')
        .where('isPublished', isEqualTo: true)
        .limit(500)
        .snapshots();
  }

  static Future<Map<String, dynamic>> loadTaskSettings(String uid) async {
    final d = await _db.collection('users').doc(uid).collection('journalSettings').doc('current').get();
    return d.data() ?? {};
  }

  static Future<void> saveTaskSettings(String uid, Map<String, dynamic> data) async {
    final ref = _db.collection('users').doc(uid).collection('journalSettings').doc('current');
    await ref.set(data, SetOptions(merge: true));
    final snap = await ref.get();
    await _archive('journal_settings', '${uid}__current', uid, snap.data() ?? <String,dynamic>{});
  }

  static Map<String, double> calculatePlan(Map<String, double> input) {
    final portfolio = input['portfolio'] ?? 0;
    final monthlyTarget = input['monthlyTargetPct'] ?? 0;

    // Risk is derived from the account and the daily objective rather than
    // using an arbitrary 3% daily-loss allowance. The plan uses a conservative
    // baseline of 0.50% account risk per trade and 1.00% maximum daily loss,
    // while never allowing the daily loss limit to exceed the calculated daily
    // target. This keeps the loss budget at or below the day's objective.
    // Position size is then derived from the planned loss and stop distance.
    final now = DateTime.now();
    final tradingDays = DateTime(now.year, now.month + 1, 0).day.toDouble();
    final tradesPerDay = 3.0;
    final stop = 1.0;
    final rr = 2.0;
    final monthlyUsd = portfolio * monthlyTarget / 100;
    final dailyUsd = monthlyUsd / tradingDays;
    final dailyPct = monthlyTarget / tradingDays;
    final maxDaily = dailyPct > 0 ? (dailyPct < 1.0 ? dailyPct : 1.0) : 0.0;
    final riskPerTrade = maxDaily / 2.0;
    final riskUsd = portfolio * riskPerTrade / 100;
    final maxDailyUsd = portfolio * maxDaily / 100;
    final double positionNotional = stop > 0 ? riskUsd / (stop / 100) : 0.0;
    final profitPerTrade = dailyUsd / tradesPerDay;
    return {
      'monthlyTargetUsd': monthlyUsd,
      'dailyTargetUsd': dailyUsd,
      'dailyTargetPct': dailyPct,
      'riskPerTradeUsd': riskUsd,
      'maxDailyRiskUsd': maxDailyUsd,
      'suggestedPositionNotional': positionNotional,
      'profitTargetPerTradeUsd': profitPerTrade,
      'tradesPerDay': tradesPerDay,
      'riskPerTradePct': riskPerTrade,
      'stopLossPct': stop,
      'riskReward': rr,
      'maxDailyRiskPct': maxDaily,
    };
  }

  static String dateKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static Future<bool> ensureTodayTask(String uid, Map<String, dynamic> plan) async {
    final ref = _db.collection('users').doc(uid).collection('journalDays').doc(dateKey());
    final existing = await ref.get();
    if (existing.exists) return false;
    await ref.set({
      'date': dateKey(),
      'dailyTargetUsd': plan['dailyTargetUsd'] ?? 0,
      'dailyTargetPct': plan['dailyTargetPct'] ?? 0,
      'status': 'OPEN',
      'generatedAt': FieldValue.serverTimestamp(),
    });
    final created = await ref.get();
    await _archive('journal_day', '${uid}__${dateKey()}', uid, created.data() ?? <String,dynamic>{});
    await _db.collection('users').doc(uid).collection('notifications').add({
      'type': 'trading_task',
      'title': 'You Have a New Trading Task',
      'body': 'Today\'s target: ${(plan['dailyTargetUsd'] ?? 0).toStringAsFixed(2)} USDT / ${(plan['dailyTargetPct'] ?? 0).toStringAsFixed(2)}%.',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    return true;
  }

  static Future<Map<String, dynamic>> loadToday(String uid) async {
    final d = await _db.collection('users').doc(uid).collection('journalDays').doc(dateKey()).get();
    return d.data() ?? {};
  }

  static Future<void> syncTodayTask(String uid, Map<String, dynamic> plan) async {
    final ref = _db.collection('users').doc(uid).collection('journalDays').doc(dateKey());
    final existing = await ref.get();
    if (!existing.exists) {
      await ensureTodayTask(uid, plan);
      return;
    }
    final data = existing.data() ?? <String, dynamic>{};
    final actual = (data['actualProfitUsd'] as num?)?.toDouble();
    final target = (plan['dailyTargetUsd'] as num?)?.toDouble() ?? 0;
    final actualCents = actual == null ? null : (actual * 100).round();
    final targetCents = (target * 100).round();
    await ref.set({
      'date': dateKey(),
      'dailyTargetUsd': target,
      'dailyTargetPct': plan['dailyTargetPct'] ?? 0,
      if (actualCents != null) 'status': actualCents >= targetCents ? 'TASK COMPLETED' : 'TARGET NOT REACHED',
    }, SetOptions(merge: true));
    final snap = await ref.get();
    await _archive('journal_day', '${uid}__${dateKey()}', uid, snap.data() ?? <String,dynamic>{});
  }

  static Future<void> saveTodayProfit(String uid, double actualUsd) async {
    final settings = await loadTaskSettings(uid);
    final portfolio = (settings['portfolio'] as num?)?.toDouble() ?? 0;
    final target = (settings['dailyTargetUsd'] as num?)?.toDouble() ?? 0;
    final pct = portfolio == 0 ? 0 : actualUsd / portfolio * 100;
    final targetPct = (settings['dailyTargetPct'] as num?)?.toDouble() ?? 0;
    final actualCents = (actualUsd * 100).round();
    final targetCents = (target * 100).round();
    await _db.collection('users').doc(uid).collection('journalDays').doc(dateKey()).set({
      'date': dateKey(),
      'actualProfitUsd': actualUsd,
      'manualProfitPct': pct,
      'dailyTargetUsd': target,
      'dailyTargetPct': targetPct,
      'status': actualCents >= targetCents ? 'TASK COMPLETED' : 'TARGET NOT REACHED',
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final snap = await _db.collection('users').doc(uid).collection('journalDays').doc(dateKey()).get();
    await _archive('journal_day', '${uid}__${dateKey()}', uid, snap.data() ?? <String,dynamic>{});
  }

  static Future<void> saveManualProfit(String uid, double profitUsd) async {
    final settings = await loadTaskSettings(uid);
    final portfolio = (settings['portfolio'] as num?)?.toDouble() ?? 0;
    final pct = portfolio == 0 ? 0 : profitUsd / portfolio * 100;
    await _db.collection('users').doc(uid).collection('journalDays').doc(dateKey()).set({
      'date': dateKey(),
      'manualProfitUsd': profitUsd,
      'manualProfitPct': pct,
      'manualUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final snap = await _db.collection('users').doc(uid).collection('journalDays').doc(dateKey()).get();
    await _archive('journal_day', '${uid}__${dateKey()}', uid, snap.data() ?? <String,dynamic>{});
  }

  static Future<List<Map<String, dynamic>>> loadPersonalDays(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('journalDays').orderBy('date', descending: true).limit(366).get();
    return snap.docs.map((d) => d.data()).toList();
  }
}
