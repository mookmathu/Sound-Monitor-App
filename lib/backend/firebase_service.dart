import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firebase structure:
//
//  alertHistory/{pushId}
//    db         : double
//    loudCount  : int
//    timestamp  : int  ← UNIX seconds (จาก ESP32) หรือ ms (จาก ServerValue)
//    zoneName   : String
//
//  sensorHistory/{pushId}
//    db         : double
//    isAlert    : bool
//    loudCount  : int
//    timestamp  : int  ← UNIX seconds
//    zoneName   : String
//
//  zones/{zone-key}
//    db         : double   ← ค่าปัจจุบัน realtime
//    isAlert    : bool
//    loudCount  : int
//    threshold  : double
//    zoneName   : String
//
//  commands/{zone-key}
//    command    : String   ← "RESET"
//    timestamp  : int
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseService {
  static final _db = FirebaseDatabase.instance;

  // ── refs ────────────────────────────────────────────────────────────────────
  static DatabaseReference get _zonesRef       => _db.ref('zones');
  static DatabaseReference get _alertHistRef   => _db.ref('alertHistory');
  static DatabaseReference get _sensorHistRef  => _db.ref('sensorHistory');
  static DatabaseReference get _settingsRef    => _db.ref('settings');

  static String _zoneKey(String name) =>
      name.toLowerCase().replaceAll(' ', '-');

  // ── timestamp helper ────────────────────────────────────────────────────────
  // Firebase ServerValue.timestamp → ms, ESP32 → seconds
  // ถ้า ts < 10^10 = seconds → ×1000
  static int toMs(int ts) => ts < 10000000000 ? ts * 1000 : ts;

  // ── parse helpers ───────────────────────────────────────────────────────────
  static Map<String, dynamic> _parseSensorEntry(MapEntry e) {
    final v = Map<String, dynamic>.from(e.value as Map);
    return {
      'key':       e.key as String,
      'zoneName':  v['zoneName']   as String? ?? '',
      'db':        (v['db']        as num?)?.toDouble() ?? 0.0,
      'loudCount': (v['loudCount'] as num?)?.toInt()   ?? 0,
      'isAlert':   v['isAlert']    as bool?  ?? false,
      'threshold': (v['threshold'] as num?)?.toDouble() ?? 40.0,
      'timestamp': toMs((v['timestamp'] as num?)?.toInt() ?? 0),
    };
  }

  static Map<String, dynamic> _parseAlertEntry(MapEntry e) {
    final v = Map<String, dynamic>.from(e.value as Map);
    return {
      'key':       e.key as String,
      'zoneName':  v['zoneName']   as String? ?? '',
      'db':        (v['db']        as num?)?.toDouble() ?? 0.0,
      'loudCount': (v['loudCount'] as num?)?.toInt()   ?? 0,
      'timestamp': toMs((v['timestamp'] as num?)?.toInt() ?? 0),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ZONES — realtime current state (ALL zones)
  // ══════════════════════════════════════════════════════════════════════════

  static Stream<List<Map<String, dynamic>>> allZonesStream() {
    return _zonesRef.onValue.map((event) {
      if (event.snapshot.value == null) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map;
      final list = data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return {
          'key':       e.key as String,
          'zoneName':  v['zoneName'] ?? e.key,
          'db':        (v['db']        as num?)?.toDouble() ?? 0.0,
          'loudCount': (v['loudCount'] as num?)?.toInt()   ?? 0,
          'isAlert':   v['isAlert']    as bool?  ?? false,
          'threshold': (v['threshold'] as num?)?.toDouble() ?? 40.0,
        };
      }).toList();

      list.sort(
        (a, b) => (a['zoneName'] as String).compareTo(b['zoneName'] as String),
      );
      return list;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ZONE — realtime สำหรับโซนเดียว (ใช้ใน HomePageMqtt)
  //  หา zone-key จาก zoneName โดยค้นใน zones/ ทั้งหมด
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream ข้อมูล realtime ของโซนเดียว
  /// [zoneName] ตรงกับ field 'zoneName' ใน Firebase เช่น "Board Game room"
  static Stream<Map<String, dynamic>> zoneStream(String zoneName) {
    // ใช้ key ที่ derive จาก zoneName
    final key = _zoneKey(zoneName);
    return _zonesRef.child(key).onValue.map((event) {
      if (event.snapshot.value == null) {
        return {
          'key':       key,
          'zoneName':  zoneName,
          'db':        0.0,
          'loudCount': 0,
          'isAlert':   false,
          'threshold': 40.0,
        };
      }
      final v = Map<String, dynamic>.from(event.snapshot.value as Map);
      return {
        'key':       key,
        'zoneName':  v['zoneName']   as String? ?? zoneName,
        'db':        (v['db']        as num?)?.toDouble() ?? 0.0,
        'loudCount': (v['loudCount'] as num?)?.toInt()   ?? 0,
        'isAlert':   v['isAlert']    as bool?  ?? false,
        'threshold': (v['threshold'] as num?)?.toDouble() ?? 40.0,
      };
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SENSOR HISTORY — ดึงตามช่วง timestamp (UNIX seconds)
  // ══════════════════════════════════════════════════════════════════════════

  static Stream<List<Map<String, dynamic>>> sensorHistoryRangeStream({
    required int startSec,
  }) {
    return _sensorHistRef
        .orderByChild('timestamp')
        .startAt(startSec.toDouble())
        .onValue
        .map((event) {
          final data = event.snapshot.value as Map?;
          if (data == null) return <Map<String, dynamic>>[];
          final list = data.entries.map(_parseSensorEntry).toList()
            ..sort((a, b) =>
                (a['timestamp'] as int).compareTo(b['timestamp'] as int));
          return list;
        });
  }

  // ── Convenience streams ──────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> historyTodayStream() {
    final now   = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return sensorHistoryRangeStream(
        startSec: start.millisecondsSinceEpoch ~/ 1000);
  }

  static Stream<List<Map<String, dynamic>>> historyLast7DaysStream() {
    final startSec = DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch ~/
        1000;
    return sensorHistoryRangeStream(startSec: startSec);
  }

  static Stream<List<Map<String, dynamic>>> historyLast8WeeksStream() {
    final startSec = DateTime.now()
            .subtract(const Duration(days: 56))
            .millisecondsSinceEpoch ~/
        1000;
    return sensorHistoryRangeStream(startSec: startSec);
  }

  static Stream<List<Map<String, dynamic>>> historyLast6MonthsStream() {
    final rough    = DateTime.now().subtract(const Duration(days: 183));
    final start    = DateTime(rough.year, rough.month, 1);
    final startSec = start.millisecondsSinceEpoch ~/ 1000;
    return sensorHistoryRangeStream(startSec: startSec);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ALERT HISTORY — 20 รายการล่าสุด
  // ══════════════════════════════════════════════════════════════════════════

  static Stream<List<Map<String, dynamic>>> alertHistoryStream() {
    return _alertHistRef
        .orderByChild('timestamp')
        .limitToLast(20)
        .onValue
        .map((event) {
          final data = event.snapshot.value as Map?;
          if (data == null) return <Map<String, dynamic>>[];
          final list = data.entries.map(_parseAlertEntry).toList()
            ..sort((a, b) =>
                (b['timestamp'] as int).compareTo(a['timestamp'] as int));
          return list;
        });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WRITE helpers
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> updateZone({
    required String zoneName,
    required double db,
    required int loudCount,
    required bool isAlert,
  }) async {
    await _zonesRef.child(_zoneKey(zoneName)).update({
      'db':        db,
      'loudCount': loudCount,
      'isAlert':   isAlert,
      'zoneName':  zoneName,
    });
  }

  /// บันทึก alertHistory
  /// timestamp ใช้ UNIX seconds (หาร 1000) เพื่อให้ตรงกับ ESP32
  static Future<void> addAlertHistory({
    required String zoneName,
    required double db,
    required int loudCount,
  }) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _alertHistRef.push().set({
      'zoneName':  zoneName,
      'db':        db,
      'loudCount': loudCount,
      'timestamp': nowSec,   // ← UNIX seconds เหมือน ESP32
    });
  }

  /// ส่งคำสั่ง RESET ไปที่ commands/{zone-key}
  static Future<void> sendResetCommand(String zoneName) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.ref('commands/${_zoneKey(zoneName)}').set({
      'command':   'RESET',
      'timestamp': nowSec,
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> updateThreshold(double value) async {
    await _settingsRef.child('threshold').set(value);
  }

  static Stream<double> thresholdStream() {
    return _settingsRef.child('threshold').onValue.map(
          (e) => (e.snapshot.value as num?)?.toDouble() ?? 40.0,
        );
  }

  static Future<void> setAutoAlert(bool value) async {
    await _settingsRef.child('autoAlert').set(value);
  }

  static Stream<bool> autoAlertStream() {
    return _settingsRef.child('autoAlert').onValue.map(
          (e) => (e.snapshot.value as bool?) ?? true,
        );
  }

  /// เขียน threshold ลง zones/{key}/threshold
  static Future<void> updateZoneThreshold(String key, double value) async {
    debugPrint('[FB] updateZoneThreshold key="$key"  value=$value');
    await _zonesRef.child(key).update({'threshold': value});
  }
}