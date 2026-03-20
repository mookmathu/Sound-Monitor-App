import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'backend/firebase_service.dart';
import 'main.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Dashboard v4 — Zone-separated Live Status & History Chart
//
//  Sections:
//   0. Overview Hero Card  → สรุปสถานะภาพรวมของวันนี้        [รวมทุกโซน]
//   1. Summary Stat Cards  → peak / เกินเกณฑ์ / โซนเงียบสุด  [รวมทุกโซน]
//   2. Live Zone Status    → per-zone tab cards               [แยกโซน]
//   3. History Chart       → per-zone tab chart               [แยกโซน / ภาพรวม]
//   4. Alert Heatmap       → alert count per zone             [รวมทุกโซน]
// ─────────────────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {

  // ── chart time-range tab ───────────────────────────────────────────────────
  int _tab = 0;
  final _tabs = ['ชั่วโมง', 'วัน', 'สัปดาห์', 'เดือน'];

  // ── zone tabs (Live + Chart share the same index) ──────────────────────────
  late TabController _liveZoneTabCtrl;
  late TabController _chartZoneTabCtrl;
  int _liveZoneIdx  = 0;  // 0 = ภาพรวมทุกโซน, 1+ = zone
  int _chartZoneIdx = 0;  // 0 = ภาพรวมทุกโซน, 1+ = zone

  // ── live pulse animation ───────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription? _zonesSub;
  StreamSubscription? _todaySub;
  StreamSubscription? _weekSub;
  StreamSubscription? _eightWeekSub;
  StreamSubscription? _sixMonthSub;
  StreamSubscription? _alertSub;

  // ── raw data ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _zones     = [];
  List<Map<String, dynamic>> _todayHist = [];
  List<Map<String, dynamic>> _weekHist  = [];
  List<Map<String, dynamic>> _8wHist    = [];
  List<Map<String, dynamic>> _6mHist    = [];
  List<Map<String, dynamic>> _alertHist = [];

  // ── chart data — ALL zones ─────────────────────────────────────────────────
  List<_Pt> _hourlyPts  = [];
  List<_Pt> _dailyPts   = [];
  List<_Pt> _weeklyPts  = [];
  List<_Pt> _monthlyPts = [];

  // ── chart data — per zone ─────────────────────────────────────────────────
  // key = zoneName, value = list of _Pt for each time tab
  Map<String, List<_Pt>> _zoneHourlyPts  = {};
  Map<String, List<_Pt>> _zoneDailyPts   = {};
  Map<String, List<_Pt>> _zoneWeeklyPts  = {};
  Map<String, List<_Pt>> _zoneMonthlyPts = {};

  // ── summary stats ──────────────────────────────────────────────────────────
  int    _totalAlertToday = 0;
  double _peakDb          = 0;
  String _peakZone        = '-';
  String _peakTime        = '-';
  String _quietZone       = '-';
  double _quietDb         = 0;
  int    _quietHours      = 0;
  double _avgDbToday      = 0;

  Map<String, int> _alertCountPerZone = {};

  bool _8wReady = false;
  bool _6mReady = false;
  String? _selectedBarLabel;

  // ── threshold helpers ──────────────────────────────────────────────────────
  double get _avgThreshold {
    if (_zones.isEmpty) return 40.0;
    final vals = _zones
        .map((z) => (z['threshold'] as num?)?.toDouble() ?? 40.0)
        .toList();
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double _zoneThreshold(String zoneName) {
    if (_zones.isEmpty) return 40.0;
    final z = _zones.firstWhere(
      (z) => (z['zoneName'] as String?) == zoneName,
      orElse: () => <String, dynamic>{},
    );
    return (z['threshold'] as num?)?.toDouble() ?? 40.0;
  }

  // ── selected zone name for chart (null = ภาพรวม) ──────────────────────────
  String? get _selectedChartZone {
    if (_chartZoneIdx == 0 || _zones.isEmpty) return null;
    final idx = _chartZoneIdx - 1;
    return idx < _zones.length ? _zones[idx]['zoneName'] as String : null;
  }

  String? get _selectedLiveZone {
    if (_liveZoneIdx == 0 || _zones.isEmpty) return null;
    final idx = _liveZoneIdx - 1;
    return idx < _zones.length ? _zones[idx]['zoneName'] as String : null;
  }

  // ── getters for current chart data ────────────────────────────────────────
  List<_Pt> get _pts {
    final zone = _selectedChartZone;
    if (zone == null) {
      // ภาพรวม
      switch (_tab) {
        case 0: return _hourlyPts;
        case 1: return _dailyPts;
        case 2: return _weeklyPts;
        case 3: return _monthlyPts;
      }
    } else {
      switch (_tab) {
        case 0: return _zoneHourlyPts[zone] ?? [];
        case 1: return _zoneDailyPts[zone] ?? [];
        case 2: return _zoneWeeklyPts[zone] ?? [];
        case 3: return _zoneMonthlyPts[zone] ?? [];
      }
    }
    return [];
  }

  double get _avg {
    final vals = _pts.map((p) => p.db).where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  String get _chartTitle => [
    'ระดับเสียงเฉลี่ยรายชั่วโมง (09–19 น.)',
    'ระดับเสียงเฉลี่ยรายวัน (7 วัน)',
    'ระดับเสียงเฉลี่ยรายสัปดาห์ (4 สัปดาห์)',
    'ระดับเสียงเฉลี่ยรายเดือน (6 เดือน)',
  ][_tab];

  double get _currentChartThreshold =>
      _selectedChartZone != null
          ? _zoneThreshold(_selectedChartZone!)
          : _avgThreshold;

  int get _alertZoneCount => _zones.where((z) => z['isAlert'] == true).length;
  int get _totalZones => _zones.length;

  // ── init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _liveZoneTabCtrl  = TabController(length: 1, vsync: this);
    _chartZoneTabCtrl = TabController(length: 1, vsync: this);

    _subZones();
    _subToday();
    _subWeek();
    _subAlerts();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _liveZoneTabCtrl.dispose();
    _chartZoneTabCtrl.dispose();
    for (final s in [
      _zonesSub, _todaySub, _weekSub, _eightWeekSub, _sixMonthSub, _alertSub
    ]) {
      s?.cancel();
    }
    super.dispose();
  }

  // ── rebuild zone tab controllers when _zones changes ──────────────────────
  void _rebuildZoneTabControllers() {
    final tabCount = _zones.length + 1; // +1 for "ภาพรวม"

    // Live zone tab
    final prevLive = _liveZoneIdx.clamp(0, tabCount - 1);
    _liveZoneTabCtrl.dispose();
    _liveZoneTabCtrl = TabController(
        length: tabCount, vsync: this, initialIndex: prevLive);
    _liveZoneTabCtrl.addListener(() {
      if (!_liveZoneTabCtrl.indexIsChanging) {
        setState(() => _liveZoneIdx = _liveZoneTabCtrl.index);
      }
    });

    // Chart zone tab
    final prevChart = _chartZoneIdx.clamp(0, tabCount - 1);
    _chartZoneTabCtrl.dispose();
    _chartZoneTabCtrl = TabController(
        length: tabCount, vsync: this, initialIndex: prevChart);
    _chartZoneTabCtrl.addListener(() {
      if (!_chartZoneTabCtrl.indexIsChanging) {
        setState(() {
          _chartZoneIdx = _chartZoneTabCtrl.index;
          _selectedBarLabel = null;
        });
      }
    });

    _liveZoneIdx  = prevLive;
    _chartZoneIdx = prevChart;
  }

  // ── subscriptions ──────────────────────────────────────────────────────────
  void _subZones() {
    _zonesSub = FirebaseService.allZonesStream().listen((z) {
      setState(() {
        _zones = z;
        _rebuildZoneTabControllers();
        _calcZoneStats();
      });
    });
  }

  void _subToday() {
    final now      = DateTime.now();
    final startSec = DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch ~/ 1000;
    _todaySub = FirebaseDatabase.instance
        .ref('sensorHistory')
        .orderByChild('timestamp')
        .startAt(startSec.toDouble())
        .limitToLast(500)
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        setState(() => _todayHist = []);
        return;
      }
      final list = data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return {
          'zoneName':  v['zoneName']   as String? ?? '',
          'db':        (v['db']        as num?)?.toDouble() ?? 0.0,
          'loudCount': (v['loudCount'] as num?)?.toInt()   ?? 0,
          'isAlert':   v['isAlert']    as bool?  ?? false,
          'timestamp': FirebaseService.toMs((v['timestamp'] as num?)?.toInt() ?? 0),
        };
      }).toList()
        ..sort((a, b) =>
            (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      setState(() {
        _todayHist = list;
        _buildHourly();
        _calcTodayStats();
      });
    });
  }

  void _subWeek() {
    final startSec = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch ~/ 1000;
    _weekSub = FirebaseDatabase.instance
        .ref('sensorHistory')
        .orderByChild('timestamp')
        .startAt(startSec.toDouble())
        .limitToLast(1000)
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        setState(() => _weekHist = []);
        return;
      }
      final list = data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return {
          'zoneName':  v['zoneName'] as String? ?? '',
          'db':        (v['db']      as num?)?.toDouble() ?? 0.0,
          'timestamp': FirebaseService.toMs((v['timestamp'] as num?)?.toInt() ?? 0),
        };
      }).toList()
        ..sort((a, b) =>
            (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      setState(() {
        _weekHist = list;
        _buildDaily();
      });
    });
  }

  void _subEightWeeks() {
    if (_8wReady) return;
    _8wReady = true;
    final startSec = DateTime.now()
        .subtract(const Duration(days: 28))
        .millisecondsSinceEpoch ~/ 1000;
    _eightWeekSub = FirebaseDatabase.instance
        .ref('sensorHistory')
        .orderByChild('timestamp')
        .startAt(startSec.toDouble())
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        setState(() => _8wHist = []);
        return;
      }
      final list = data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return {
          'zoneName':  v['zoneName'] as String? ?? '',
          'db':        (v['db']      as num?)?.toDouble() ?? 0.0,
          'timestamp': FirebaseService.toMs((v['timestamp'] as num?)?.toInt() ?? 0),
        };
      }).toList()
        ..sort((a, b) =>
            (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      setState(() {
        _8wHist = list;
        _buildWeekly();
      });
    });
  }

  void _subSixMonths() {
    if (_6mReady) return;
    _6mReady = true;
    final rough    = DateTime.now().subtract(const Duration(days: 183));
    final start    = DateTime(rough.year, rough.month, 1);
    final startSec = start.millisecondsSinceEpoch ~/ 1000;
    _sixMonthSub = FirebaseDatabase.instance
        .ref('sensorHistory')
        .orderByChild('timestamp')
        .startAt(startSec.toDouble())
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        setState(() => _6mHist = []);
        return;
      }
      final list = data.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return {
          'zoneName':  v['zoneName'] as String? ?? '',
          'db':        (v['db']      as num?)?.toDouble() ?? 0.0,
          'timestamp': FirebaseService.toMs((v['timestamp'] as num?)?.toInt() ?? 0),
        };
      }).toList()
        ..sort((a, b) =>
            (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      setState(() {
        _6mHist = list;
        _buildMonthly();
      });
    });
  }

  void _subAlerts() {
    _alertSub = FirebaseService.alertHistoryStream().listen((list) {
      final counts = <String, int>{};
      for (final e in list) {
        final z = e['zoneName'] as String;
        counts[z] = (counts[z] ?? 0) + 1;
      }
      setState(() {
        _alertHist = list;
        _alertCountPerZone = counts;
      });
    });
  }

  void _onTabTap(int i) {
    setState(() { _tab = i; _selectedBarLabel = null; });
    if (i == 2) _subEightWeeks();
    if (i == 3) _subSixMonths();
  }

  // ── stats calculators ──────────────────────────────────────────────────────
  void _calcZoneStats() {
    if (_zones.isEmpty) return;
    _totalAlertToday =
        _zones.fold(0, (s, z) => s + (z['loudCount'] as int));

    final peak = _zones.reduce(
        (a, b) => (a['db'] as double) >= (b['db'] as double) ? a : b);
    _peakDb   = peak['db'] as double;
    _peakZone = peak['zoneName'] as String;

    final quiet = _zones.reduce(
        (a, b) => (a['db'] as double) <= (b['db'] as double) ? a : b);
    _quietZone = quiet['zoneName'] as String;
    _quietDb   = quiet['db'] as double;
  }

  void _calcTodayStats() {
    if (_todayHist.isEmpty) return;

    final peak = _todayHist.reduce(
        (a, b) => (a['db'] as double) >= (b['db'] as double) ? a : b);
    final ts  = DateTime.fromMillisecondsSinceEpoch(peak['timestamp'] as int);
    _peakTime =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')} น.';
    if ((peak['db'] as double) > _peakDb) {
      _peakDb   = peak['db'] as double;
      _peakZone = peak['zoneName'] as String;
    }

    final vals = _todayHist.map((e) => e['db'] as double).toList();
    _avgDbToday =
        vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

    _quietHours = _hourlyPts
        .where((p) {
          final h = int.tryParse(p.label) ?? -1;
          return h >= 9 && h <= 19 && p.db > 0 && p.db < _avgThreshold;
        })
        .length;
  }

  // ── chart builders (ALL zones + per zone) ─────────────────────────────────
  void _buildHourly() {
    // ── All zones
    final buckets = {for (int h = 9; h <= 19; h++) h: <double>[]};
    for (final e in _todayHist) {
      final h = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int).hour;
      buckets[h]?.add(e['db'] as double);
    }
    _hourlyPts = buckets.entries.map((e) {
      final avg = e.value.isEmpty
          ? 0.0
          : e.value.reduce((a, b) => a + b) / e.value.length;
      return _Pt(e.key.toString().padLeft(2, '0'), avg);
    }).toList();

    // ── Per zone
    final zoneNames = _zones.map((z) => z['zoneName'] as String).toSet();
    _zoneHourlyPts = {};
    for (final zone in zoneNames) {
      final zb = {for (int h = 9; h <= 19; h++) h: <double>[]};
      for (final e in _todayHist.where((e) => e['zoneName'] == zone)) {
        final h = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int).hour;
        zb[h]?.add(e['db'] as double);
      }
      _zoneHourlyPts[zone] = zb.entries.map((e) {
        final avg = e.value.isEmpty
            ? 0.0
            : e.value.reduce((a, b) => a + b) / e.value.length;
        return _Pt(e.key.toString().padLeft(2, '0'), avg);
      }).toList();
    }
  }

  void _buildDaily() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final keys  = <String>[];
    final buckets = <String, List<double>>{};
    for (int d = 6; d >= 0; d--) {
      final day = today.subtract(Duration(days: d));
      final k   = '${day.day}/${day.month}';
      keys.add(k);
      buckets[k] = [];
    }
    for (final e in _weekHist) {
      final ts = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int);
      final k  = '${ts.day}/${ts.month}';
      buckets[k]?.add(e['db'] as double);
    }
    _dailyPts = keys.map((k) {
      final vals = buckets[k]!;
      final avg  =
          vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
      return _Pt(k, avg);
    }).toList();

    // ── Per zone
    final zoneNames = _zones.map((z) => z['zoneName'] as String).toSet();
    _zoneDailyPts = {};
    for (final zone in zoneNames) {
      final zb = {for (final k in keys) k: <double>[]};
      for (final e in _weekHist.where((e) => e['zoneName'] == zone)) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int);
        final k  = '${ts.day}/${ts.month}';
        zb[k]?.add(e['db'] as double);
      }
      _zoneDailyPts[zone] = keys.map((k) {
        final vals = zb[k]!;
        final avg  = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
        return _Pt(k, avg);
      }).toList();
    }
  }

  void _buildWeekly() {
    final now        = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    List<_Pt> _buildForHistory(List<Map<String, dynamic>> hist) =>
        List.generate(4, (i) {
          final w     = 3 - i;
          final start = thisMonday.subtract(Duration(days: w * 7));
          final end   = start.add(const Duration(days: 7));
          final label = w == 0 ? 'สัปดาห์นี้' : '${start.day}/${start.month}';
          final vals  = hist.where((e) {
            final ts = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int);
            return !ts.isBefore(start) && ts.isBefore(end);
          }).map((e) => e['db'] as double).toList();
          final avg = vals.isEmpty
              ? 0.0
              : vals.reduce((a, b) => a + b) / vals.length;
          return _Pt(label, avg);
        });

    _weeklyPts = _buildForHistory(_8wHist);

    // ── Per zone
    final zoneNames = _zones.map((z) => z['zoneName'] as String).toSet();
    _zoneWeeklyPts = {};
    for (final zone in zoneNames) {
      _zoneWeeklyPts[zone] = _buildForHistory(
          _8wHist.where((e) => e['zoneName'] == zone).toList());
    }
  }

  void _buildMonthly() {
    final now = DateTime.now();
    final thaiMonths = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];

    List<_Pt> _buildForHistory(List<Map<String, dynamic>> hist) =>
        List.generate(6, (i) {
          final ref   = DateTime(now.year, now.month - (5 - i), 1);
          final start = DateTime(ref.year, ref.month, 1);
          final end   = DateTime(
            ref.month == 12 ? ref.year + 1 : ref.year,
            ref.month == 12 ? 1 : ref.month + 1,
            1,
          );
          final vals = hist.where((e) {
            final ts = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int);
            return !ts.isBefore(start) && ts.isBefore(end);
          }).map((e) => e['db'] as double).toList();
          final avg = vals.isEmpty
              ? 0.0
              : vals.reduce((a, b) => a + b) / vals.length;
          return _Pt(thaiMonths[ref.month - 1], avg);
        });

    _monthlyPts = _buildForHistory(_6mHist);

    // ── Per zone
    final zoneNames = _zones.map((z) => z['zoneName'] as String).toSet();
    _zoneMonthlyPts = {};
    for (final zone in zoneNames) {
      _zoneMonthlyPts[zone] = _buildForHistory(
          _6mHist.where((e) => e['zoneName'] == zone).toList());
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  Color _dbColor(double db, {double threshold = 40.0}) {
    if (db >= threshold) return AppColors.danger;
    return AppColors.safe;
  }

  Color _dbBg(double db, {double threshold = 40.0}) {
    if (db >= threshold) return AppColors.dangerBg;
    return AppColors.safeBg;
  }

  String _dbLabel(double db, {double threshold = 40.0}) {
    if (db >= threshold) return 'เกินเกณฑ์!';
    return 'ปกติ';
  }

  IconData _dbIcon(double db, {double threshold = 40.0}) {
    if (db >= threshold) return Icons.volume_up_rounded;
    return Icons.volume_off_rounded;
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc     = isDark ? AppColors.darkText   : AppColors.lightText;
    final mc     = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final cc     = isDark ? AppColors.darkCard   : AppColors.lightCard;
    final bc     = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final now      = DateTime.now();
    final dayNames = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];
    final mthNames = [
      'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
      'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
    ];
    final dateStr = '${dayNames[now.weekday - 1]}ที่ ${now.day} '
        '${mthNames[now.month - 1]} ${now.year + 543}';

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [

            // ════════════════════════════════════════════════════════════════
            //  HEADER
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('แดชบอร์ด',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: tc)),
                        Text(dateStr,
                            style: TextStyle(fontSize: 11, color: mc)),
                      ],
                    ),
                  ),
                  _AnimatedLiveBadge(anim: _pulseAnim),
                ]),
              ),
            ),

            // ════════════════════════════════════════════════════════════════
            //  SECTION 0: OVERVIEW HERO CARD   [รวมทุกโซน]
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: _OverviewHeroCard(
                  zones: _zones,
                  alertZoneCount: _alertZoneCount,
                  totalZones: _totalZones,
                  avgDb: _avgDbToday,
                  totalAlerts: _totalAlertToday,
                  pulseAnim: _pulseAnim,
                  isDark: isDark,
                ),
              ),
            ),

            // ════════════════════════════════════════════════════════════════
            //  SECTION 1: SUMMARY STAT CARDS   [รวมทุกโซน]
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('สรุปภาพรวมวันนี้', tc),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.warning_amber_rounded,
                          label: 'เกินเกณฑ์วันนี้',
                          value: _totalAlertToday.toString(),
                          unit: 'ครั้ง',
                          sub: 'รวมทุกโซน',
                          color: AppColors.danger,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.trending_up_rounded,
                          label: 'Peak วันนี้',
                          value: _peakDb > 0 ? _peakDb.toStringAsFixed(0) : '-',
                          unit: _peakDb > 0 ? 'dB' : '',
                          sub: _peakDb > 0
                              ? '$_peakZone · $_peakTime'
                              : 'ยังไม่มีข้อมูล',
                          color: AppColors.warn,
                          isDark: isDark,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.volume_off_rounded,
                          label: 'โซนเงียบสุด',
                          value: _quietZone.isNotEmpty ? _quietZone : '-',
                          unit: '',
                          sub: _quietDb > 0
                              ? '${_quietDb.toStringAsFixed(0)} dB ปัจจุบัน'
                              : 'ยังไม่มีข้อมูล',
                          color: AppColors.safe,
                          isDark: isDark,
                          small: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.schedule_rounded,
                          label: 'ชั่วโมงเงียบ\n(09–19 น.)',
                          value: _quietHours.toString(),
                          unit: 'ชม.',
                          sub: 'จาก 10 ชม. (< 50 dB)',
                          color: AppColors.accent,
                          isDark: isDark,
                        ),
                      ),
                    ]),
                    if (_avgDbToday > 0) ...[
                      const SizedBox(height: 8),
                      _AvgDbBanner(avgDb: _avgDbToday, isDark: isDark),
                    ],
                  ],
                ),
              ),
            ),

            // ════════════════════════════════════════════════════════════════
            //  SECTION 2: LIVE ZONE STATUS   [แยกโซน + ภาพรวม]
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _SectionLabel('สถานะโซนแบบ Real-time', tc),
                      const Spacer(),
                      if (_alertZoneCount > 0)
                        _AlertChip(count: _alertZoneCount),
                    ]),
                    const SizedBox(height: 10),

                    if (_zones.isEmpty)
                      _EmptyCard('กำลังโหลดข้อมูลโซน...', mc, cc, bc)
                    else
                      Column(children: [
                        // ── Zone tab bar ─────────────────────────────────
                        _ZoneTabBar(
                          controller: _liveZoneTabCtrl,
                          zones: _zones,
                          isDark: isDark,
                          mc: mc,
                          cc: cc,
                          bc: bc,
                        ),
                        const SizedBox(height: 10),

                        // ── Tab content ──────────────────────────────────
                        if (_liveZoneIdx == 0)
                          // ภาพรวมทุกโซน
                          Column(
                            children: _zones.map((z) {
                              final db      = z['db'] as double;
                              final zName   = z['zoneName'] as String;
                              final lc      = z['loudCount'] as int;
                              final isAlert = z['isAlert'] as bool? ?? false;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ZoneCard(
                                  name: zName,
                                  db: db,
                                  loudCount: lc,
                                  isAlert: isAlert,
                                  isDark: isDark,
                                  threshold: _zoneThreshold(zName),
                                  dbColor: _dbColor(db, threshold: _zoneThreshold(zName)),
                                  dbBg: _dbBg(db, threshold: _zoneThreshold(zName)),
                                  label: _dbLabel(db, threshold: _zoneThreshold(zName)),
                                  dbIcon: _dbIcon(db, threshold: _zoneThreshold(zName)),
                                ),
                              );
                            }).toList(),
                          )
                        else
                          // โซนที่เลือก
                          Builder(builder: (_) {
                            final idx = _liveZoneIdx - 1;
                            if (idx >= _zones.length) return const SizedBox.shrink();
                            final z       = _zones[idx];
                            final db      = z['db'] as double;
                            final zName   = z['zoneName'] as String;
                            final lc      = z['loudCount'] as int;
                            final isAlert = z['isAlert'] as bool? ?? false;
                            return _ZoneCard(
                              name: zName,
                              db: db,
                              loudCount: lc,
                              isAlert: isAlert,
                              isDark: isDark,
                              threshold: _zoneThreshold(zName),
                              dbColor: _dbColor(db, threshold: _zoneThreshold(zName)),
                              dbBg: _dbBg(db, threshold: _zoneThreshold(zName)),
                              label: _dbLabel(db, threshold: _zoneThreshold(zName)),
                              dbIcon: _dbIcon(db, threshold: _zoneThreshold(zName)),
                            );
                          }),
                      ]),
                  ],
                ),
              ),
            ),

            // ════════════════════════════════════════════════════════════════
            //  SECTION 3: HISTORY CHART   [แยกโซน + ภาพรวม]
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _SectionLabel('ประวัติระดับเสียง', tc),
                      const Spacer(),
                      _Dot(AppColors.safe, '<${_currentChartThreshold.toInt()} dB'),
                      const SizedBox(width: 8),
                      _Dot(AppColors.danger, '≥${_currentChartThreshold.toInt()} dB'),
                    ]),
                    const SizedBox(height: 10),

                    // ── Zone tab bar ───────────────────────────────────────
                    if (_zones.isNotEmpty)
                      _ZoneTabBar(
                        controller: _chartZoneTabCtrl,
                        zones: _zones,
                        isDark: isDark,
                        mc: mc,
                        cc: cc,
                        bc: bc,
                      ),

                    const SizedBox(height: 10),

                    // ── Time-range tab selector ────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: cc,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: bc),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: List.generate(_tabs.length, (i) {
                          final active = i == _tab;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _onTabTap(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  _tabs[i],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color:
                                        active ? Colors.white : mc,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 10),

                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _chartTitle,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: tc),
                                  ),
                                  if (_selectedChartZone != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        _selectedChartZone!,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.accent,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_avg > 0)
                              _Badge('เฉลี่ย ${_avg.toStringAsFixed(0)} dB',
                                  AppColors.accent, AppColors.accentBg),
                          ]),
                          const SizedBox(height: 14),
                          _buildHistoryChart(mc, tc, bc, isDark),
                          const SizedBox(height: 14),
                          if (_pts.isNotEmpty && _pts.any((p) => p.db > 0))
                            _buildChartSummary(tc, mc, bc, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ════════════════════════════════════════════════════════════════
            //  SECTION 4: ALERT COUNT PER ZONE   [รวมทุกโซน]
            // ════════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('การแจ้งเตือนแยกตามโซน', tc),
                    const SizedBox(height: 8),
                    if (_alertCountPerZone.isEmpty)
                      _EmptyCard('ยังไม่มีประวัติการแจ้งเตือน', mc, cc, bc)
                    else
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('(จาก alertHistory 20 รายการล่าสุด)',
                                style: TextStyle(fontSize: 10, color: mc)),
                            const SizedBox(height: 12),
                            ..._alertZoneBarRows(mc),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  // ── history chart widget ───────────────────────────────────────────────────
  Widget _buildHistoryChart(Color mc, Color tc, Color bc, bool isDark) {
    final loading =
        (_tab == 2 && !_8wReady) || (_tab == 3 && !_6mReady);
    if (loading) {
      return const SizedBox(
          height: 140,
          child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent)));
    }
    final pts = _pts;
    if (pts.isEmpty || pts.every((p) => p.db == 0)) {
      return SizedBox(
          height: 140,
          child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart_rounded, size: 32, color: bc),
                  const SizedBox(height: 6),
                  Text('ยังไม่มีข้อมูลในช่วงเวลานี้',
                      style: TextStyle(fontSize: 12, color: mc)),
                ],
              )));
    }

    final rawMax = pts.map((p) => p.db).reduce((a, b) => a > b ? a : b);
    final scale  =
        (((rawMax / 20).ceil() * 20).clamp(80, 100)).toDouble();
    final threshold = _currentChartThreshold;
    const chartH    = 140.0;
    const yAxisW    = 28.0;

    final yTicks = <int>[];
    for (int v = 0; v <= scale.toInt(); v += 20) {
      yTicks.add(v);
    }

    final peakIdx = pts.indexWhere((p) =>
        p.db == pts.map((q) => q.db).reduce((a, b) => a > b ? a : b));

    return _HistoryBarChart(
      pts: pts,
      scale: scale,
      threshold: threshold,
      chartH: chartH,
      yAxisW: yAxisW,
      yTicks: yTicks,
      peakIdx: peakIdx,
      mc: mc,
      tc: tc,
      bc: bc,
      isDark: isDark,
      dbColor: (db) => _dbColor(db, threshold: _currentChartThreshold),
      onSelected: (label) => setState(() => _selectedBarLabel = label),
    );
  }

  Widget _buildChartSummary(Color tc, Color mc, Color bc, bool isDark) {
    final sel = _selectedBarLabel;

    List<Map<String, dynamic>> rawHist;
    switch (_tab) {
      case 0: rawHist = _todayHist; break;
      case 1: rawHist = _weekHist;  break;
      case 2: rawHist = _8wHist;    break;
      case 3: rawHist = _6mHist;    break;
      default: rawHist = [];
    }

    // Filter by zone if a specific zone is selected
    final zone = _selectedChartZone;
    if (zone != null) {
      rawHist = rawHist.where((e) => e['zoneName'] == zone).toList();
    }

    List<double> rawVals;
    if (sel == null) {
      rawVals = rawHist.map((e) => e['db'] as double).where((v) => v > 0).toList();
    } else {
      rawVals = rawHist.where((e) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int);
        switch (_tab) {
          case 0:
            final h = int.tryParse(sel) ?? -1;
            return ts.hour == h;
          case 1:
            return '${ts.day}/${ts.month}' == sel;
          case 2:
            final now = DateTime.now();
            final thisMonday = DateTime(now.year, now.month, now.day)
                .subtract(Duration(days: now.weekday - 1));
            final idx = _weeklyPts.indexWhere((p) => p.label == sel);
            if (idx < 0) return false;
            final start = thisMonday.subtract(Duration(days: (3 - idx) * 7));
            final end   = start.add(const Duration(days: 7));
            return !ts.isBefore(start) && ts.isBefore(end);
          case 3:
            final thaiMonths = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
              'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
            final mIdx = thaiMonths.indexOf(sel);
            return mIdx >= 0 && ts.month == mIdx + 1;
          default: return true;
        }
      }).map((e) => e['db'] as double).where((v) => v > 0).toList();
    }

    final vals = rawVals.isNotEmpty ? rawVals : _pts.where((p) => p.db > 0).map((p) => p.db).toList();
    if (vals.isEmpty) return const SizedBox.shrink();
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final avgV = vals.reduce((a, b) => a + b) / vals.length;

    final divColor =
        isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkBorder.withOpacity(0.4)
            : AppColors.lightBorder.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: IntrinsicHeight(
        child: Row(children: [
          Expanded(
            child: _SummaryChip(
              label: 'สูงสุด',
              value: maxV.toStringAsFixed(0),
              unit: 'dB',
              color: _dbColor(maxV, threshold: _currentChartThreshold),
              icon: Icons.arrow_upward_rounded,
            ),
          ),
          VerticalDivider(width: 1, color: divColor),
          Expanded(
            child: _SummaryChip(
              label: 'เฉลี่ย',
              value: avgV.toStringAsFixed(0),
              unit: 'dB',
              color: AppColors.accent,
              icon: Icons.remove_rounded,
            ),
          ),
          VerticalDivider(width: 1, color: divColor),
          Expanded(
            child: _SummaryChip(
              label: 'ต่ำสุด',
              value: minV.toStringAsFixed(0),
              unit: 'dB',
              color: _dbColor(minV, threshold: _currentChartThreshold),
              icon: Icons.arrow_downward_rounded,
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _alertZoneBarRows(Color mc) {
    final entries = _alertCountPerZone.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = entries.first.value.toDouble();

    return entries.map((e) {
      final pct   = (e.value / maxCount).clamp(0.0, 1.0);
      final color = e.value >= 5
          ? AppColors.danger
          : e.value >= 3
              ? AppColors.warn
              : AppColors.safe;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.key,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500, color: mc)),
            ),
            Text('${e.value} ครั้ง',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ]),
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Zone Tab Bar — reusable tab selector with "ภาพรวม" + zone tabs
// ─────────────────────────────────────────────────────────────────────────────
class _ZoneTabBar extends StatelessWidget {
  final TabController controller;
  final List<Map<String, dynamic>> zones;
  final bool isDark;
  final Color mc, cc, bc;

  const _ZoneTabBar({
    required this.controller,
    required this.zones,
    required this.isDark,
    required this.mc,
    required this.cc,
    required this.bc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bc),
      ),
      padding: const EdgeInsets.all(3),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.zero,
        indicator: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(9),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: mc,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        tabs: [
          const Tab(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.layers_rounded, size: 12),
              SizedBox(width: 5),
              Text('ภาพรวม'),
            ]),
          )),
          ...zones.map((z) {
            final isAlert = z['isAlert'] as bool? ?? false;
            return Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isAlert) ...[
                    const Icon(Icons.warning_rounded, size: 10),
                    const SizedBox(width: 3),
                  ] else ...[
                    const Icon(Icons.sensors_rounded, size: 10),
                    const SizedBox(width: 3),
                  ],
                  Text(z['zoneName'] as String),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Overview Hero Card
// ─────────────────────────────────────────────────────────────────────────────
class _OverviewHeroCard extends StatelessWidget {
  final List<Map<String, dynamic>> zones;
  final int alertZoneCount;
  final int totalZones;
  final double avgDb;
  final int totalAlerts;
  final Animation<double> pulseAnim;
  final bool isDark;

  const _OverviewHeroCard({
    required this.zones,
    required this.alertZoneCount,
    required this.totalZones,
    required this.avgDb,
    required this.totalAlerts,
    required this.pulseAnim,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final mc = isDark ? AppColors.darkMuted : AppColors.lightMuted;

    Color heroColor;
    Color heroBg;
    IconData heroIcon;
    String heroTitle;
    String heroSub;

    if (zones.isEmpty) {
      heroColor = AppColors.accent;
      heroBg    = AppColors.accentBg;
      heroIcon  = Icons.sensors_rounded;
      heroTitle = 'กำลังโหลด...';
      heroSub   = 'รอรับข้อมูลจาก Firebase';
    } else if (alertZoneCount > 0) {
      heroColor = AppColors.danger;
      heroBg    = AppColors.dangerBg;
      heroIcon  = Icons.notification_important_rounded;
      heroTitle = '$alertZoneCount/$totalZones โซน กำลังแจ้งเตือน';
      heroSub   = 'มีเสียงเกินเกณฑ์ — ต้องให้ความสนใจ';
    } else if (avgDb >= 50) {
      heroColor = AppColors.warn;
      heroBg    = AppColors.warnBg;
      heroIcon  = Icons.volume_down_rounded;
      heroTitle = 'ห้องสมุดค่อนข้างดัง';
      heroSub   = 'เฉลี่ย ${avgDb.toStringAsFixed(1)} dB — ยังไม่เกินเกณฑ์';
    } else {
      heroColor = AppColors.safe;
      heroBg    = AppColors.safeBg;
      heroIcon  = Icons.library_books_rounded;
      heroTitle = 'ห้องสมุดเงียบสงบ';
      heroSub   = avgDb > 0
          ? 'เฉลี่ย ${avgDb.toStringAsFixed(1)} dB — ระดับดีเยี่ยม'
          : 'ทุกโซนปกติ';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            heroColor.withOpacity(isDark ? 0.22 : 0.13),
            heroColor.withOpacity(isDark ? 0.08 : 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: heroColor.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: heroColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(heroIcon, color: heroColor, size: 22),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: heroColor.withOpacity(pulseAnim.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: heroColor.withOpacity(0.4 * pulseAnim.value),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('LIVE',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: heroColor,
                  letterSpacing: 0.8)),
        ]),

        const SizedBox(height: 14),

        Text(heroTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: heroColor,
                height: 1.2)),
        const SizedBox(height: 4),
        Text(heroSub, style: TextStyle(fontSize: 12, color: mc)),

        const SizedBox(height: 16),

        if (zones.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: zones.map((z) {
              final db      = z['db'] as double;
              final name    = z['zoneName'] as String;
              final isAlert = z['isAlert'] as bool? ?? false;
              Color c;
              if (db >= 70) c = AppColors.danger;
              else if (db >= 50) c = AppColors.warn;
              else c = AppColors.safe;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.withOpacity(isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: c.withOpacity(isAlert ? 0.7 : 0.3),
                      width: isAlert ? 1.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isAlert) ...[
                    Icon(Icons.circle, size: 6, color: c),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '$name  ${db.toStringAsFixed(0)} dB',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: c),
                  ),
                ]),
              );
            }).toList(),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Zone card
// ─────────────────────────────────────────────────────────────────────────────
class _ZoneCard extends StatelessWidget {
  final String name, label;
  final double db;
  final double threshold;
  final int loudCount;
  final bool isAlert, isDark;
  final Color dbColor, dbBg;
  final IconData dbIcon;

  const _ZoneCard({
    required this.name,
    required this.db,
    required this.loudCount,
    required this.isAlert,
    required this.isDark,
    required this.threshold,
    required this.dbColor,
    required this.dbBg,
    required this.label,
    required this.dbIcon,
  });

  @override
  Widget build(BuildContext context) {
    final tc = isDark ? AppColors.darkText   : AppColors.lightText;
    final mc = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final bc = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cc = isDark ? AppColors.darkCard   : AppColors.lightCard;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAlert
            ? AppColors.danger.withOpacity(isDark ? 0.08 : 0.04)
            : cc,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAlert ? AppColors.danger.withOpacity(0.5) : bc,
          width: isAlert ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dbBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(dbIcon, size: 18, color: dbColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: tc)),
          ),
          if (isAlert)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_rounded,
                    size: 11, color: AppColors.danger),
                const SizedBox(width: 3),
                const Text('แจ้งเตือน',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger)),
              ]),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: dbBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: dbColor)),
            ),
        ]),

        const SizedBox(height: 12),

        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: db.toStringAsFixed(0),
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: dbColor,
                      height: 1)),
              TextSpan(
                  text: ' dB',
                  style: TextStyle(fontSize: 11, color: mc)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (db / 100).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: bc,
                      valueColor: AlwaysStoppedAnimation(dbColor),
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (ctx, box) => Stack(clipBehavior: Clip.none, children: [
                        Positioned(
                          left: box.maxWidth * (threshold / 100).clamp(0.0, 1.0) - 1,
                          top: -3,
                          child: Container(
                            width: 2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0', style: TextStyle(fontSize: 8, color: mc)),
                      Text('เกณฑ์ ${threshold.toInt()} dB',
                          style: TextStyle(fontSize: 8, color: mc)),
                      Text('100', style: TextStyle(fontSize: 8, color: mc)),
                    ]),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: loudCount > 0
                  ? AppColors.danger.withOpacity(0.1)
                  : bc,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              Text(loudCount.toString(),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color:
                          loudCount > 0 ? AppColors.danger : mc,
                      height: 1)),
              Text('ครั้ง', style: TextStyle(fontSize: 8, color: mc)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────
class _Pt {
  final String label;
  final double db;
  const _Pt(this.label, this.db);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: color));
}

class _AnimatedLiveBadge extends StatelessWidget {
  final Animation<double> anim;
  const _AnimatedLiveBadge({required this.anim});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.safeBg,
          borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: anim,
          builder: (_, __) => Opacity(
            opacity: anim.value,
            child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: AppColors.safe, shape: BoxShape.circle)),
          ),
        ),
        const SizedBox(width: 5),
        const Text('LIVE',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.safe,
                letterSpacing: 0.5)),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value, unit, sub;
  final Color color;
  final bool isDark, small;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.color,
    required this.isDark,
    this.small = false,
  });
  @override
  Widget build(BuildContext context) {
    final mc = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? AppColors.darkBorder : AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
              blurRadius: 8)
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: mc,
                        fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 8),
            RichText(
                text: TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: small ? 16 : 26,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1)),
              if (unit.isNotEmpty)
                TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: 11, color: mc)),
            ])),
            const SizedBox(height: 3),
            Text(sub,
                style: TextStyle(fontSize: 9.5, color: mc),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ]),
    );
  }
}

class _AvgDbBanner extends StatelessWidget {
  final double avgDb;
  final bool isDark;
  const _AvgDbBanner({required this.avgDb, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final mc = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    Color col;
    IconData iconData;
    String text;
    if (avgDb <= 0) {
      col = AppColors.accent;
      iconData = Icons.graphic_eq_rounded;
      text = 'กำลังโหลดข้อมูลเฉลี่ย...';
    } else if (avgDb < 50) {
      col = AppColors.safe;
      iconData = Icons.sentiment_satisfied_rounded;
      text = 'เฉลี่ยวันนี้ ${avgDb.toStringAsFixed(1)} dB — ห้องสมุดเงียบสงบดี';
    } else if (avgDb < 70) {
      col = AppColors.warn;
      iconData = Icons.sentiment_neutral_rounded;
      text = 'เฉลี่ยวันนี้ ${avgDb.toStringAsFixed(1)} dB — เสียงค่อนข้างดัง';
    } else {
      col = AppColors.danger;
      iconData = Icons.warning_rounded;
      text = 'เฉลี่ยวันนี้ ${avgDb.toStringAsFixed(1)} dB — เกินมาตรฐาน!';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: col.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: col.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(iconData, color: col, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: col,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final int count;
  const _AlertChip({required this.count});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.dangerBg,
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.notification_important_rounded,
              color: AppColors.danger, size: 14),
          const SizedBox(width: 4),
          Text('$count โซนกำลังแจ้งเตือน',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger)),
        ]),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final Color mc, cc, bc;
  const _EmptyCard(this.text, this.mc, this.cc, this.bc);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
            color: cc,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: bc)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.inbox_rounded, size: 28, color: mc),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mc)),
        ]),
      );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const _Badge(this.text, this.fg, this.bg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      );
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot(this.color, this.label);
  @override
  Widget build(BuildContext context) {
    final mc = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkMuted
        : AppColors.lightMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 9.5, color: mc)),
    ]);
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  final IconData icon;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final mc = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkMuted
        : AppColors.lightMuted;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(height: 3),
      RichText(
          text: TextSpan(children: [
        TextSpan(
            text: value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1)),
        TextSpan(
            text: ' $unit', style: TextStyle(fontSize: 9, color: mc)),
      ])),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 9.5, color: mc)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  History bar chart
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryBarChart extends StatefulWidget {
  final List<_Pt> pts;
  final double scale, threshold, chartH, yAxisW;
  final List<int> yTicks;
  final int peakIdx;
  final Color mc, tc, bc;
  final bool isDark;
  final Color Function(double) dbColor;
  final void Function(String? label)? onSelected;

  const _HistoryBarChart({
    required this.pts,
    required this.scale,
    required this.threshold,
    required this.chartH,
    required this.yAxisW,
    required this.yTicks,
    required this.peakIdx,
    required this.mc,
    required this.tc,
    required this.bc,
    required this.isDark,
    required this.dbColor,
    this.onSelected,
  });

  @override
  State<_HistoryBarChart> createState() => _HistoryBarChartState();
}

class _HistoryBarChartState extends State<_HistoryBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final pts       = widget.pts;
    final scale     = widget.scale;
    final chartH    = widget.chartH;
    final yAxisW    = widget.yAxisW;
    final mc        = widget.mc;
    final tc        = widget.tc;
    final bc        = widget.bc;
    final threshold = widget.threshold;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: chartH,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: yAxisW,
            child: Stack(
              children: widget.yTicks.map((v) {
                final frac = v / scale;
                return Positioned(
                  bottom: chartH * frac - 6,
                  left: 0,
                  right: 2,
                  child: Text('$v',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 8, color: mc)),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: Stack(children: [
              ...widget.yTicks.map((v) {
                final frac = v / scale;
                return Positioned(
                  bottom: chartH * frac,
                  left: 0,
                  right: 0,
                  child: Container(
                      height: 1,
                      color: v == 0 ? bc : bc.withOpacity(0.5)),
                );
              }),

              Positioned(
                bottom: chartH * (threshold / scale),
                left: 0,
                right: 0,
                child: Row(
                  children: List.generate(
                    18,
                    (i) => Expanded(
                      child: Container(
                        height: 1.5,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 2),
                        color: i.isEven
                            ? AppColors.danger.withOpacity(0.55)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: pts.asMap().entries.map((entry) {
                  final i        = entry.key;
                  final p        = entry.value;
                  final sel      = _selected == i;
                  final isPeak   = i == widget.peakIdx && p.db > 0;
                  final barColor = widget.dbColor(p.db);
                  final heightFrac = p.db > 0
                      ? (p.db / scale).clamp(0.04, 1.0)
                      : 0.0;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                          setState(() => _selected = _selected == i ? null : i);
                          widget.onSelected?.call(_selected != null ? pts[i].label : null);
                        },
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedOpacity(
                              duration:
                                  const Duration(milliseconds: 150),
                              opacity: (sel || isPeak) && p.db > 0
                                  ? 1.0
                                  : 0.0,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 3),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? barColor
                                      : barColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(p.db.toInt().toString(),
                                    style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                        color: sel
                                            ? Colors.white
                                            : barColor)),
                              ),
                            ),
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              height: chartH * heightFrac,
                              decoration: BoxDecoration(
                                color: p.db == 0
                                    ? bc.withOpacity(0.3)
                                    : sel
                                        ? barColor
                                        : isPeak
                                            ? barColor
                                            : barColor.withOpacity(0.7),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                                boxShadow:
                                    (sel || isPeak) && p.db > 0
                                        ? [
                                            BoxShadow(
                                                color: barColor
                                                    .withOpacity(0.35),
                                                blurRadius: 6,
                                                offset:
                                                    const Offset(0, 2))
                                          ]
                                        : null,
                                border: isPeak && !sel
                                    ? Border.all(
                                        color:
                                            barColor.withOpacity(0.8),
                                        width: 1.5)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ]),
          ),
        ]),
      ),

      Padding(
        padding: EdgeInsets.only(left: yAxisW),
        child: Row(
          children: pts.asMap().entries.map((e) {
            final sel = _selected == e.key;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(e.value.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: sel ? 9.5 : 8,
                        fontWeight: sel
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: sel ? AppColors.accent : mc)),
              ),
            );
          }).toList(),
        ),
      ),

      if (_selected == null)
        Padding(
          padding: EdgeInsets.only(left: yAxisW, top: 6),
          child: Row(children: [
            Icon(Icons.touch_app_rounded, size: 11, color: mc),
            const SizedBox(width: 4),
            Text('แตะแท่งเพื่อดูค่า',
                style: TextStyle(fontSize: 9.5, color: mc)),
          ]),
        ),

      if (_selected != null && _selected! < pts.length)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: 1.0,
          child: Container(
            margin: EdgeInsets.only(left: yAxisW, top: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget
                  .dbColor(pts[_selected!].db)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: widget
                      .dbColor(pts[_selected!].db)
                      .withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.bar_chart_rounded,
                  size: 14,
                  color: widget.dbColor(pts[_selected!].db)),
              const SizedBox(width: 8),
              Text(pts[_selected!].label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tc)),
              const Spacer(),
              Text(
                pts[_selected!].db == 0
                    ? 'ไม่มีข้อมูล'
                    : '${pts[_selected!].db.toStringAsFixed(1)} dB',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.dbColor(pts[_selected!].db)),
              ),
              const SizedBox(width: 6),
              if (pts[_selected!].db > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget
                        .dbColor(pts[_selected!].db)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pts[_selected!].db >= widget.threshold
                        ? 'เกินเกณฑ์'
                        : 'ปกติ',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color:
                            widget.dbColor(pts[_selected!].db)),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}