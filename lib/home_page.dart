import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';
import "backend/firebase_service.dart";

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _zones = [];
  bool _isLoading = true;

  StreamSubscription? _zonesSub;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // threshold ดึงจาก Firebase ต่อโซน
  ZoneStatus _statusOf(Map<String, dynamic> z) {
    final db        = z['db'] as double;
    final isAlert   = z['isAlert'] as bool;
    final threshold = (z['threshold'] as num?)?.toDouble() ?? 40.0;
    if (isAlert || db >= threshold) return ZoneStatus.loud;
    if (db >= threshold * 0.75)     return ZoneStatus.moderate;
    return ZoneStatus.quiet;
  }

  double get _avgDb {
    if (_zones.isEmpty) return 0;
    return _zones.map((z) => z['db'] as double).reduce((a, b) => a + b) /
        _zones.length;
  }

  int get _alertZoneCount =>
      _zones.where((z) => _statusOf(z) == ZoneStatus.loud).length;

  // ── icon by keyword in zone name ──────────────────────────────────────────
  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('game') || n.contains('เกม'))       return Icons.casino_rounded;
    if (n.contains('computer') || n.contains('คอม'))   return Icons.computer_rounded;
    if (n.contains('quiet') || n.contains('เงียบ'))    return Icons.do_not_disturb_on_rounded;
    if (n.contains('meet') || n.contains('ประชุม'))    return Icons.groups_rounded;
    if (n.contains('study') || n.contains('อ่าน'))     return Icons.menu_book_rounded;
    if (n.contains('kids') || n.contains('เด็ก'))      return Icons.child_care_rounded;
    return Icons.library_books_rounded;
  }

  // ── overall status ────────────────────────────────────────────────────────
  double get _avgThreshold {
    if (_zones.isEmpty) return 40.0;
    final vals = _zones.map((z) => (z['threshold'] as num?)?.toDouble() ?? 40.0).toList();
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  _OverallStatus get _overallStatus {
    if (_alertZoneCount > 0)         return _OverallStatus.alert;
    if (_avgDb >= _avgThreshold * 0.9) return _OverallStatus.moderate;
    return _OverallStatus.safe;
  }

  String get _overallLabel {
    switch (_overallStatus) {
      case _OverallStatus.alert:    return 'มีโซนเกินเกณฑ์';
      case _OverallStatus.moderate: return 'เริ่มดัง';
      case _OverallStatus.safe:     return 'เงียบสงบ';
    }
  }

  IconData get _overallIcon {
    switch (_overallStatus) {
      case _OverallStatus.alert:    return Icons.warning_rounded;
      case _OverallStatus.moderate: return Icons.graphic_eq_rounded;
      case _OverallStatus.safe:     return Icons.eco_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 0.2).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _subscribeZones();
  }

  void _subscribeZones() {
    _zonesSub = FirebaseService.allZonesStream().listen(
      (zones) {
        if (!mounted) return;
        setState(() { _zones = zones; _isLoading = false; });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _zonesSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final textColor  = isDark ? AppColors.darkText  : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkMuted : AppColors.lightMuted;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [

          // ── App bar ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 16, 6),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ห้องสมุด', style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 4),
                    Row(children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Opacity(
                          opacity: _pulse.value,
                          child: Container(width: 6, height: 6,
                              decoration: const BoxDecoration(
                                  color: AppColors.safe, shape: BoxShape.circle)),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text('LIVE', style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.safe, letterSpacing: 1)),
                      Text(' · Firebase Realtime',
                          style: TextStyle(fontSize: 10, color: mutedColor)),
                    ]),
                  ],
                )),
                Stack(clipBehavior: Clip.none, children: [
                  _SmallIconBtn(
                    icon: Icons.notifications_outlined,
                    onTap: () {},
                  ),
                  if (_alertZoneCount > 0)
                    Positioned(top: -3, right: -3,
                      child: Container(width: 10, height: 10,
                          decoration: const BoxDecoration(
                              color: AppColors.danger, shape: BoxShape.circle)),
                    ),
                ]),
              ]),
            ),
          ),

          // ── Overall index card ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B8EF4), Color(0xFF7EB0FF)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(
                      color: AppColors.accent.withOpacity(0.28),
                      blurRadius: 24, offset: const Offset(0, 8))],
                ),
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 66, height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4), width: 2.5),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_avgDb.toInt().toString(), style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700,
                            color: Colors.white, height: 1)),
                        const Text('dB', style: TextStyle(
                            fontSize: 10, color: Colors.white70)),
                      ]),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ระดับเสียงรวมขณะนี้',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(_overallIcon, color: Colors.white, size: 17),
                        const SizedBox(width: 6),
                        Text(_overallLabel, style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'เกณฑ์ < ${_avgThreshold.toInt()} dB · '
                        '${_zones.length - _alertZoneCount}/${_zones.length} โซนปกติ',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70)),
                    ],
                  )),
                ]),
              ),
            ),
          ),

          // ── Section label ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('โซนทั้งหมด', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: mutedColor, letterSpacing: 1.5)),
                  Text('${_zones.length} โซน', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: mutedColor)),
                ],
              ),
            ),
          ),

          // ── Empty state ────────────────────────────────────────────────────
          if (_zones.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(children: [
                    Icon(Icons.sensors_off_rounded,
                        size: 40, color: mutedColor),
                    const SizedBox(height: 10),
                    Text('ยังไม่มีข้อมูลโซน', style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: textColor)),
                    const SizedBox(height: 4),
                    Text('รอเซ็นเซอร์ส่งข้อมูลมายัง Firebase',
                        style: TextStyle(fontSize: 12, color: mutedColor)),
                  ]),
                ),
              ),
            ),

          // ── Zone cards ────────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final z       = _zones[i];
              final status  = _statusOf(z);
              final db      = z['db'] as double;
              final name    = z['zoneName'] as String;
              final isAlert = z['isAlert'] as bool;

              return _ZoneCard(
                icon: _iconFor(name),
                name: name,
                sub: 'เซ็นเซอร์ · ${z['key']}',
                db: db,
                threshold: (z['threshold'] as num?)?.toDouble() ?? 40.0,
                status: status,
                isAlert: isAlert,
                loudCount: z['loudCount'] as int,
              );
            }, childCount: _zones.length),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ]),
      ),
    );
  }
}

enum _OverallStatus { safe, moderate, alert }

// ── Zone Card ─────────────────────────────────────────────────────────────────
class _ZoneCard extends StatelessWidget {
  final IconData icon;
  final String name, sub;
  final double db, threshold;
  final ZoneStatus status;
  final bool isAlert;
  final int loudCount;

  const _ZoneCard({
    required this.icon,
    required this.name,
    required this.sub,
    required this.db,
    required this.threshold,
    required this.status,
    required this.isAlert,
    required this.loudCount,
  });

  Color get _statusColor {
    switch (status) {
      case ZoneStatus.quiet:    return AppColors.safe;
      case ZoneStatus.moderate: return AppColors.warn;
      case ZoneStatus.loud:     return AppColors.danger;
    }
  }

  Color get _statusBg {
    switch (status) {
      case ZoneStatus.quiet:    return AppColors.safeBg;
      case ZoneStatus.moderate: return AppColors.warnBg;
      case ZoneStatus.loud:     return AppColors.dangerBg;
    }
  }

  String get _statusLabel {
    if (isAlert) return 'ALERT!';
    switch (status) {
      case ZoneStatus.quiet:    return 'เงียบ';
      case ZoneStatus.moderate: return 'ปกติ';
      case ZoneStatus.loud:     return 'เกินเกณฑ์!';
    }
  }

  List<Color> get _barGradient {
    switch (status) {
      case ZoneStatus.quiet:
        return [const Color(0xFF34C97A), const Color(0xFF5DE89C)];
      case ZoneStatus.moderate:
        return [const Color(0xFFF5A623), const Color(0xFFFFC95C)];
      case ZoneStatus.loud:
        return [const Color(0xFFF25F5C), const Color(0xFFFF8C8A)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final cardColor   = isDark ? AppColors.darkCard   : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final mutedColor  = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final textColor   = isDark ? AppColors.darkText   : AppColors.lightText;
    final fillPct     = (db / 100).clamp(0.0, 1.0);

    final cardBorder = isAlert
        ? Border.all(color: AppColors.danger.withOpacity(0.5), width: 1.5)
        : Border.all(color: borderColor);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: cardBorder,
        boxShadow: [BoxShadow(
          color: isAlert
              ? AppColors.danger.withOpacity(0.08)
              : Colors.black.withOpacity(isDark ? 0.25 : 0.05),
          blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // ── Top row ──────────────────────────────────────────────────────────
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: _statusBg, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Icon(icon, size: 16, color: _statusColor)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
              Text(sub, style: TextStyle(fontSize: 10, color: mutedColor)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: _statusBg, borderRadius: BorderRadius.circular(20)),
            child: Text(_statusLabel, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor)),
          ),
        ]),

        const SizedBox(height: 10),

        // ── dB + bar ──────────────────────────────────────────────────────────
        Row(children: [
          RichText(text: TextSpan(children: [
            TextSpan(text: db.toStringAsFixed(1), style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w700,
                color: _statusColor, height: 1)),
            TextSpan(text: ' dB',
                style: TextStyle(fontSize: 11, color: mutedColor)),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(children: [
                  Container(height: 8, decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(6))),
                  FractionallySizedBox(
                    widthFactor: fillPct,
                    child: Container(height: 8, decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _barGradient),
                      borderRadius: BorderRadius.circular(6),
                    )),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: TextStyle(fontSize: 9, color: mutedColor)),
                  Text('เกณฑ์ ${threshold.toInt()}',
                      style: TextStyle(fontSize: 9, color: mutedColor)),
                  Text('100', style: TextStyle(fontSize: 9, color: mutedColor)),
                ]),
            ],
          )),
        ]),

        // ── Loud count dots ───────────────────────────────────────────────────
        if (loudCount > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text('ดังต่อเนื่อง ',
                style: TextStyle(fontSize: 9, color: mutedColor)),
            ...List.generate(3, (i) => Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < loudCount ? AppColors.danger : borderColor,
              ),
            )),
            Text(' $loudCount/3 ครั้ง',
                style: TextStyle(fontSize: 9, color: mutedColor)),
          ]),
        ],
      ]),
    );
  }
}

// ── Small icon button ─────────────────────────────────────────────────────────
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
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)
          ],
        ),
        child: Center(child: Icon(icon, size: 18,
            color: isDark ? AppColors.darkText : AppColors.lightText)),
      ),
    );
  }
}