import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import 'firebase_service.dart';

class HomePageMqtt extends StatefulWidget {
  const HomePageMqtt({super.key});

  @override
  State<HomePageMqtt> createState() => _HomePageMqttState();
}

class _HomePageMqttState extends State<HomePageMqtt>
    with SingleTickerProviderStateMixin {

  double  _db        = 0.0;
  int     _loudCount = 0;
  bool    _isAlert   = false;
  String  _zoneName  = 'Board Game room';
  bool    _isResetting = false;
  bool    _isLoading   = true;

  static const int _alertThreshold = 3;
  StreamSubscription? _zoneSub;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  ZoneStatus get _zoneStatus {
    if (_isAlert || _db >= 40) return ZoneStatus.loud;
    if (_db >= 25)             return ZoneStatus.moderate;
    return ZoneStatus.quiet;
  }

  Color get _statusColor {
    switch (_zoneStatus) {
      case ZoneStatus.loud:     return AppColors.danger;
      case ZoneStatus.moderate: return AppColors.warn;
      case ZoneStatus.quiet:    return AppColors.safe;
    }
  }

  Color get _statusBg {
    switch (_zoneStatus) {
      case ZoneStatus.loud:     return AppColors.dangerBg;
      case ZoneStatus.moderate: return AppColors.warnBg;
      case ZoneStatus.quiet:    return AppColors.safeBg;
    }
  }

  IconData get _statusIcon {
    if (_isAlert)  return Icons.warning_rounded;
    if (_db >= 40) return Icons.volume_up_rounded;
    if (_db >= 25) return Icons.graphic_eq_rounded;
    return Icons.volume_off_rounded;
  }

  String get _statusLabel {
    if (_isAlert)  return 'ALERT! เสียงดังเกินกำหนด';
    if (_db >= 40) return 'ดัง ($_loudCount/$_alertThreshold ครั้ง)';
    if (_db >= 25) return 'ปกติ';
    return 'เงียบ';
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 0.6).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _subscribeFirebase();
  }

  void _subscribeFirebase() {
    _zoneSub = FirebaseService.zoneStream(_zoneName).listen((data) {
      if (!mounted) return;
      final wasAlert = _isAlert;
      final newAlert = data['isAlert'] as bool;
      setState(() {
        _db        = data['db'] as double;
        _loudCount = data['loudCount'] as int;
        _isAlert   = newAlert;
        _zoneName  = data['zoneName'] as String;
        _isLoading = false;
      });
      // บันทึก alert history เมื่อเกิด ALERT ใหม่
      if (!wasAlert && newAlert) {
        FirebaseService.addAlertHistory(
            zoneName: _zoneName, db: _db, loudCount: _loudCount);
      }
    }, onError: (e) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _zoneSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetAlert() async {
    setState(() => _isResetting = true);
    try {
      await FirebaseService.sendResetCommand(_zoneName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('รีเซ็ตการแจ้งเตือนแล้ว'),
        ]),
        backgroundColor: AppColors.safe,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('รีเซ็ตไม่สำเร็จ: $e')),
        ]),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final textColor   = isDark ? AppColors.darkText   : AppColors.lightText;
    final mutedColor  = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final cardColor   = isDark ? AppColors.darkCard   : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [

          // ── Header ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Noise Monitor',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 4),
                    Row(children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Opacity(
                          opacity: _pulse.value,
                          child: Container(width: 7, height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.safe, shape: BoxShape.circle)),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text('LIVE', style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w700, color: AppColors.safe, letterSpacing: 1)),
                      Text(' · Firebase Realtime',
                          style: TextStyle(fontSize: 10, color: mutedColor)),
                    ]),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.accentBg, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on_rounded,
                        size: 12, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(_zoneName,
                        style: const TextStyle(fontSize: 11, color: AppColors.accent,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          ),

          // ── ALERT banner ──────────────────────────────────────────────
          if (_isAlert)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Opacity(
                    opacity: _pulse.value,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF8080), Color(0xFFF25F5C)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                            color: AppColors.danger.withOpacity(0.3),
                            blurRadius: 18, offset: const Offset(0, 6))],
                      ),
                      child: const Row(children: [
                        Icon(Icons.volume_up_rounded,
                            color: Colors.white, size: 30),
                        SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ตรวจพบเสียงดังเกินเกณฑ์!',
                                style: TextStyle(fontSize: 14,
                                    fontWeight: FontWeight.w700, color: Colors.white)),
                            SizedBox(height: 2),
                            Text('กรุณากดรีเซ็ตหลังแจ้งเตือนผู้ใช้แล้ว',
                                style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        )),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

          // ── dB card ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _statusColor.withOpacity(0.5), width: 2),
                  boxShadow: [BoxShadow(color: _statusColor.withOpacity(0.12),
                      blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Column(children: [
                  Text('${_db.toStringAsFixed(1)} dB',
                      style: TextStyle(fontSize: 60, fontWeight: FontWeight.w800,
                          color: _statusColor, height: 1)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: _statusBg, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_statusIcon, size: 13, color: _statusColor),
                      const SizedBox(width: 5),
                      Text(_statusLabel,
                          style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w600, color: _statusColor)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (_db / 100).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: borderColor,
                      valueColor: AlwaysStoppedAnimation(_statusColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0 dB', style: TextStyle(fontSize: 9, color: mutedColor)),
                      Text('เกณฑ์ 40 dB', style: TextStyle(fontSize: 9, color: mutedColor)),
                      Text('100 dB', style: TextStyle(fontSize: 9, color: mutedColor)),
                    ],
                  ),
                ]),
              ),
            ),
          ),

          // ── Loud count card ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                      blurRadius: 12, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('จำนวนครั้งที่เสียงดัง',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w600, color: textColor)),
                        Text('$_loudCount / $_alertThreshold ครั้ง',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: _loudCount >= _alertThreshold
                                    ? AppColors.danger : AppColors.accent)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(_alertThreshold, (i) {
                        final filled = i < _loudCount;
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 14,
                            decoration: BoxDecoration(
                              color: filled ? AppColors.danger : borderColor,
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: filled
                                  ? [BoxShadow(
                                      color: AppColors.danger.withOpacity(0.3),
                                      blurRadius: 6)]
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text('ครบ $_alertThreshold ครั้ง = แจ้งเตือนบรรณารักษ์',
                        style: TextStyle(fontSize: 10, color: mutedColor)),
                  ],
                ),
              ),
            ),
          ),

          // ── RESET / Status ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _isAlert
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isResetting ? null : _resetAlert,
                        icon: _isResetting
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                          _isResetting ? 'กำลังรีเซ็ต...' : 'รีเซ็ตการแจ้งเตือน',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.danger.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.safeBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.safe.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.safe),
                          SizedBox(width: 8),
                          Text('ระดับเสียงอยู่ในเกณฑ์ปกติ',
                              style: TextStyle(color: AppColors.safe,
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
            ),
          ),

        ]),
      ),
    );
  }
}