import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';
import 'backend/firebase_service.dart';

class AlertPage extends StatefulWidget {
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage> {

  List<Map<String, dynamic>> _zones   = [];
  List<Map<String, dynamic>> _history = [];

  double  _db          = 0.0;
  int     _loudCount   = 0;
  bool    _isAlert     = false;
  String  _zoneName    = '-';
  bool    _isResetting = false;
  String? _resettingZoneKey;

  // ── History pagination ──────────────────────────────────────────────────────
  static const int _pageSize   = 5;   // แสดงครั้งแรก 5 รายการ
  int              _visibleCount = _pageSize;

  StreamSubscription? _zonesSub;
  StreamSubscription? _historySub;

  Map<String, dynamic>? get _focusZone {
    if (_zones.isEmpty) return null;
    final alerting = _zones.where((z) => z['isAlert'] as bool).toList();
    final pool     = alerting.isNotEmpty ? alerting : _zones;
    return pool.reduce(
        (a, b) => (a['db'] as double) >= (b['db'] as double) ? a : b);
  }

  int get _alertZoneCount =>
      _zones.where((z) => z['isAlert'] as bool).length;

  double get _threshold {
    final z = _focusZone;
    if (z == null) return 40.0;
    return (z['threshold'] as num?)?.toDouble() ?? 40.0;
  }

  // ── items ที่แสดงจริง ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _visibleHistory =>
      _history.take(_visibleCount).toList();

  bool get _hasMore => _history.length > _visibleCount;

  @override
  void initState() {
    super.initState();
    _subscribeZones();
    _subscribeHistory();
  }

  void _subscribeZones() {
    _zonesSub = FirebaseService.allZonesStream().listen((zones) {
      if (!mounted) return;

      bool resetConfirmed = false;
      if (_isResetting && _resettingZoneKey != null) {
        final resetZone = zones.firstWhere(
          (z) => z['key'] == _resettingZoneKey,
          orElse: () => {},
        );
        if (resetZone.isNotEmpty && !(resetZone['isAlert'] as bool)) {
          resetConfirmed = true;
        }
      }

      setState(() {
        _zones = zones;
        final z = _focusZone;
        if (z != null) {
          _db        = z['db']        as double;
          _loudCount = z['loudCount'] as int;
          _isAlert   = z['isAlert']   as bool;
          _zoneName  = z['zoneName']  as String;
        }
        if (resetConfirmed) {
          _isResetting      = false;
          _resettingZoneKey = null;
        }
      });

      if (resetConfirmed) {
        _showSnack('บอร์ดรีเซ็ตสำเร็จแล้ว', AppColors.safe,
            icon: Icons.check_circle_rounded);
      }
    });
  }

  void _subscribeHistory() {
    _historySub = FirebaseService.alertHistoryStream().listen((list) {
      if (!mounted) return;
      setState(() {
        _history = list;
        // ถ้ามีข้อมูลใหม่เข้ามาและ _visibleCount ยังน้อยกว่าที่มี ไม่ต้องรีเซ็ต
      });
    });
  }

  @override
  void dispose() {
    _zonesSub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  // ── โหลดเพิ่ม ──────────────────────────────────────────────────────────────
  void _loadMore() {
    setState(() => _visibleCount += _pageSize);
  }

  Future<void> _resetAlert() async {
    final currentZone = _focusZone;
    if (currentZone == null) return;

    final zoneKey  = currentZone['key']      as String;
    final zoneName = currentZone['zoneName'] as String;

    setState(() { _isResetting = true; _resettingZoneKey = zoneKey; });

    try {
      await FirebaseService.sendResetCommand(zoneName);
      _showSnack('ส่งคำสั่ง RESET แล้ว รออุปกรณ์ตอบกลับ…', AppColors.accent,
          icon: Icons.send_rounded);

      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _isResetting && _resettingZoneKey == zoneKey) {
          setState(() { _isResetting = false; _resettingZoneKey = null; });
          _showSnack('อุปกรณ์ไม่ตอบสนอง ลองใหม่อีกครั้ง', AppColors.warn,
              icon: Icons.warning_rounded);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isResetting = false; _resettingZoneKey = null; });
      _showSnack('ส่งคำสั่งไม่สำเร็จ: $e', AppColors.danger,
          icon: Icons.error_rounded);
    }
  }

  void _showSnack(String msg, Color color, {required IconData icon}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  String _formatTs(int tsMs) {
    if (tsMs == 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} '
           '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} น.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final textColor   = isDark ? AppColors.darkText   : AppColors.lightText;
    final mutedColor  = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final cardColor   = isDark ? AppColors.darkCard   : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final excess = (_db - _threshold).clamp(0.0, 100.0);
    final visible = _visibleHistory;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [

          // ── App bar ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 16, 6),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('แจ้งเตือน', style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700,
                        color: textColor)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 13,
                          color: _alertZoneCount > 0
                              ? AppColors.danger : AppColors.safe),
                      const SizedBox(width: 4),
                      Text(
                        _alertZoneCount > 0
                            ? '$_alertZoneCount โซนเกินเกณฑ์ขณะนี้'
                            : 'ไม่มีโซนเกินเกณฑ์',
                        style: TextStyle(
                            fontSize: 11,
                            color: _alertZoneCount > 0
                                ? AppColors.danger : AppColors.safe,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ],
                )),
                _SmallIconBtn(icon: Icons.notifications_off_outlined,
                    onTap: () {}),
              ]),
            ),
          ),

          // ── Alert banner ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isAlert
                        ? [const Color(0xFFFF8080), const Color(0xFFF25F5C)]
                        : [AppColors.safe.withOpacity(0.85),
                           const Color(0xFF28B369)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(
                      color: (_isAlert ? AppColors.danger : AppColors.safe)
                          .withOpacity(0.28),
                      blurRadius: 20, offset: const Offset(0, 8))],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(child: Icon(
                      _isAlert
                          ? Icons.volume_up_rounded
                          : Icons.check_circle_rounded,
                      color: Colors.white, size: 24)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAlert
                            ? 'ตรวจพบเสียงดังเกินเกณฑ์'
                            : 'ระดับเสียงปกติ',
                        style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isAlert
                            ? 'กรุณากดรีเซ็ตเพื่อให้บอร์ดกลับสู่ปกติ'
                            : 'ระดับ ${_db.toStringAsFixed(1)} dB · ต่ำกว่าเกณฑ์',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  )),
                ]),
              ),
            ),
          ),

          // ── Section: โซนที่ต้องดำเนินการ ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text('โซนที่ต้องดำเนินการ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: mutedColor, letterSpacing: 1.5)),
            ),
          ),

          // ── Live zone card ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isAlert
                        ? AppColors.danger.withOpacity(0.4)
                        : borderColor,
                    width: 1.5,
                  ),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                      blurRadius: 12, offset: const Offset(0, 2))],
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Icon(Icons.location_on_rounded,
                            size: 14, color: mutedColor),
                        const SizedBox(width: 4),
                        Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_zoneName, style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: textColor)),
                            const SizedBox(height: 2),
                            Text('ระดับเสียง realtime',
                                style: TextStyle(
                                    fontSize: 10, color: mutedColor)),
                          ]),
                      ]),
                      // status chip
                      _isResetting
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppColors.accentBg,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(width: 10, height: 10,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: AppColors.accent)),
                                  SizedBox(width: 6),
                                  Text('รอบอร์ด…', style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent)),
                                ]))
                          : _isAlert
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: AppColors.dangerBg,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.access_time_rounded,
                                          size: 11, color: AppColors.danger),
                                      SizedBox(width: 3),
                                      Text('กำลังเกิน', style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.danger)),
                                    ]))
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: AppColors.safeBg,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.check_rounded,
                                          size: 11, color: AppColors.safe),
                                      SizedBox(width: 3),
                                      Text('ปกติ', style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.safe)),
                                    ])),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // dB row
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RichText(text: TextSpan(children: [
                        TextSpan(
                          text: _db.toStringAsFixed(1),
                          style: TextStyle(fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: _isAlert
                                  ? AppColors.danger : AppColors.safe,
                              height: 1),
                        ),
                        TextSpan(text: ' dB',
                            style: TextStyle(fontSize: 13, color: mutedColor)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('เกณฑ์: ${_threshold.toInt()} dB',
                              style: TextStyle(fontSize: 11,
                                  color: mutedColor)),
                          const SizedBox(height: 2),
                          Text(
                            _isAlert
                                ? '+${excess.toStringAsFixed(1)} dB เกินไป'
                                : '${(_threshold - _db).abs().toStringAsFixed(1)} dB ต่ำกว่าเกณฑ์',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isAlert
                                    ? AppColors.danger : AppColors.safe),
                          ),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(children: [
                      Container(height: 8, color: borderColor),
                      FractionallySizedBox(
                        widthFactor: (_db / 100).clamp(0.0, 1.0),
                        child: Container(height: 8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _isAlert
                                  ? [const Color(0xFFF25F5C),
                                     const Color(0xFFFF8C8A)]
                                  : [const Color(0xFF34C97A),
                                     const Color(0xFF5DE89C)]),
                              borderRadius: BorderRadius.circular(6),
                            )),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // Loud count dots
                  if (_loudCount > 0) ...[
                    Row(children: [
                      Text('ดังต่อเนื่อง ',
                          style: TextStyle(fontSize: 10, color: mutedColor)),
                      ...List.generate(3, (i) => Container(
                        width: 10, height: 10,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _loudCount
                              ? AppColors.danger : borderColor,
                        ),
                      )),
                      Text('$_loudCount/3',
                          style: TextStyle(fontSize: 10, color: mutedColor)),
                    ]),
                    const SizedBox(height: 10),
                  ],

                  // Reset button
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isResetting || !_isAlert)
                            ? null : _resetAlert,
                        icon: _isResetting
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          _isResetting ? 'รอบอร์ด…' : 'รีเซ็ต',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.accent.withOpacity(0.35),
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),

          // ── Section: ประวัติล่าสุด ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
              child: Row(children: [
                Expanded(
                  child: Text('ประวัติล่าสุด',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mutedColor, letterSpacing: 1.5)),
                ),
                // badge จำนวนทั้งหมด
                if (_history.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_history.length} รายการ',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger),
                    ),
                  ),
              ]),
            ),
          ),

          // ── History list ──────────────────────────────────────────────────────
          if (_history.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor)),
                  child: Column(children: [
                    Icon(Icons.notifications_none_rounded,
                        size: 32, color: mutedColor),
                    const SizedBox(height: 8),
                    Text('ยังไม่มีประวัติ',
                        style: TextStyle(fontSize: 13, color: mutedColor)),
                  ]),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(
                            isDark ? 0.3 : 0.06),
                        blurRadius: 10)],
                  ),
                  child: Column(children: [

                    // ── รายการที่มองเห็น ──────────────────────────────────────
                    ...visible.asMap().entries.map((e) {
                      final idx     = e.key;
                      final item    = e.value;
                      final isLast  = idx == visible.length - 1 && !_hasMore;
                      final dbVal   = (item['db'] as num).toDouble();
                      final ts      = item['timestamp'] as int;
                      final zone    = item['zoneName'] as String? ?? '-';
                      final lc      = (item['loudCount'] as num?)?.toInt() ?? 0;

                      return Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          child: Row(children: [

                            // ── icon ──────────────────────────────────────────
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                  color: AppColors.dangerBg,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Center(child: Icon(
                                  Icons.volume_up_rounded,
                                  size: 16, color: AppColors.danger)),
                            ),
                            const SizedBox(width: 12),

                            // ── zone + time ───────────────────────────────────
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(zone,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textColor)),
                                const SizedBox(height: 3),
                                Text(_formatTs(ts),
                                    style: TextStyle(
                                        fontSize: 10, color: mutedColor)),
                              ],
                            )),

                            // ── dB + count ────────────────────────────────────
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: AppColors.dangerBg,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(
                                    '${dbVal.toStringAsFixed(1)} dB',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.danger),
                                  ),
                                ),
                                if (lc > 0) ...[
                                  const SizedBox(height: 3),
                                  Text('เกิน $lc ครั้ง',
                                      style: TextStyle(
                                          fontSize: 9, color: mutedColor)),
                                ],
                              ],
                            ),
                          ]),
                        ),
                        if (!isLast)
                          Divider(height: 1, color: borderColor,
                              indent: 16, endIndent: 16),
                      ]);
                    }),

                    // ── ปุ่ม "ดูเพิ่มเติม" ─────────────────────────────────────
                    if (_hasMore)
                      Column(children: [
                        Divider(height: 1, color: borderColor),
                        InkWell(
                          onTap: _loadMore,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(18)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.expand_more_rounded,
                                    size: 16, color: AppColors.accent),
                                const SizedBox(width: 6),
                                Text(
                                  'ดูเพิ่มเติม '
                                  '(${_history.length - _visibleCount} รายการ)',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]),

                    // ── "แสดงทั้งหมดแล้ว" เมื่อหมด ────────────────────────────
                    if (!_hasMore && _history.length > _pageSize)
                      Column(children: [
                        Divider(height: 1, color: borderColor),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'แสดงทั้งหมด ${_history.length} รายการ',
                            style: TextStyle(
                                fontSize: 11, color: mutedColor),
                          ),
                        ),
                      ]),

                  ]),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),

        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small icon button
// ─────────────────────────────────────────────────────────────────────────────
class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SmallIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08), blurRadius: 8),
          ],
        ),
        child: Center(child: Icon(icon, size: 18,
            color: isDark ? AppColors.darkText : AppColors.lightText)),
      ),
    );
  }
}