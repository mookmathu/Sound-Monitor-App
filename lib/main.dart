import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_page.dart';
import 'dashboard.dart';
import 'alert.dart';
import 'setting.dart';
import 'firebase_options.dart';
import 'backend/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  ThemeMode _themeMode = ThemeMode.system;

  void setTheme(bool dark) {
    setState(() {
      _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Library Sound Monitor',

      themeMode: _themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,

      home: const MainShell(),
    );
  }
}

// ── Color tokens ──────────────────────────────────────────────────────────────
class AppColors {
  static const safe     = Color(0xFF34C97A);
  static const safeBg   = Color(0x1F34C97A);
  static const warn     = Color(0xFFF5A623);
  static const warnBg   = Color(0x1FF5A623);
  static const danger   = Color(0xFFF25F5C);
  static const dangerBg = Color(0x1FF25F5C);
  static const accent   = Color(0xFF5B8EF4);
  static const accentBg = Color(0x1A5B8EF4);
  static const teal     = Color(0xFF3ECFB2);
  static const tealBg   = Color(0x1A3ECFB2);

  static const lightBg      = Color(0xFFF4F6FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard    = Color(0xFFFFFFFF);
  static const lightBorder  = Color(0xFFE8ECF5);
  static const lightText    = Color(0xFF1E2640);
  static const lightText2   = Color(0xFF4A5378);
  static const lightMuted   = Color(0xFF9AA3C0);

  static const darkBg      = Color(0xFF13161F);
  static const darkSurface = Color(0xFF1C2030);
  static const darkCard    = Color(0xFF1C2030);
  static const darkBorder  = Color(0xFF2C3354);
  static const darkText    = Color(0xFFE8ECF8);
  static const darkText2   = Color(0xFF9AA3C0);
  static const darkMuted   = Color(0xFF5A6285);
}

// ── Theme ─────────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    fontFamily: 'Kodchasan',
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      surface: AppColors.lightSurface,
    ),
    cardTheme: CardTheme(
      color: AppColors.lightCard, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    fontFamily: 'Kodchasan',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.darkSurface,
    ),
    cardTheme: CardTheme(
      color: AppColors.darkCard, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

// ── Zone model ────────────────────────────────────────────────────────────────
enum ZoneStatus { quiet, moderate, loud }

class ZoneData {
  final String id, name, location;
  final IconData icon;
  final double db, threshold;
  final ZoneStatus status;

  const ZoneData({
    required this.id, required this.name, required this.location,
    required this.icon, required this.db, required this.threshold,
    required this.status,
  });

  double get percent => (db / 100).clamp(0.0, 1.0);
  double get thresholdPercent => (threshold / 100).clamp(0.0, 1.0);

  Color get statusColor {
    switch (status) {
      case ZoneStatus.quiet:    return AppColors.safe;
      case ZoneStatus.moderate: return AppColors.warn;
      case ZoneStatus.loud:     return AppColors.danger;
    }
  }

  Color get statusBgColor {
    switch (status) {
      case ZoneStatus.quiet:    return AppColors.safeBg;
      case ZoneStatus.moderate: return AppColors.warnBg;
      case ZoneStatus.loud:     return AppColors.dangerBg;
    }
  }

  String get statusLabel {
    switch (status) {
      case ZoneStatus.quiet:    return 'เงียบ';
      case ZoneStatus.moderate: return 'ดังขึ้น';
      case ZoneStatus.loud:     return 'เกินเกณฑ์!';
    }
  }
}

final List<ZoneData> mockZones = const [
  ZoneData(id:'A', name:'โซน A · หนังสือทั่วไป', location:'ชั้น 1 · เซ็นเซอร์ #001',
      icon:Icons.library_books_rounded,      db:34, threshold:40, status:ZoneStatus.quiet),
  ZoneData(id:'B', name:'โซน B · คอมพิวเตอร์',  location:'ชั้น 1 · เซ็นเซอร์ #002',
      icon:Icons.computer_rounded,            db:52, threshold:45, status:ZoneStatus.moderate),
  ZoneData(id:'C', name:'โซน C · ประชุมกลุ่ม',  location:'ชั้น 2 · เซ็นเซอร์ #003',
      icon:Icons.groups_rounded,              db:71, threshold:55, status:ZoneStatus.loud),
  ZoneData(id:'D', name:'โซน D · ห้องเงียบ',    location:'ชั้น 2 · เซ็นเซอร์ #004',
      icon:Icons.do_not_disturb_on_rounded,   db:28, threshold:40, status:ZoneStatus.quiet),
];

// ── Main shell ────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // ── alert state ──────────────────────────────────────────────────────────
  int  _alertCount   = 0;   // number of zones currently alerting
  bool _bannerVisible = false;
  String _bannerText = '';

  StreamSubscription? _zonesSub;
  Set<String> _prevAlertKeys = {};  // track which zones were already alerting

  // ── banner animation ─────────────────────────────────────────────────────
  late AnimationController _bannerCtrl;
  late Animation<Offset>   _bannerSlide;

  final List<Widget> _pages = const [
    HomePage(),
    DashboardPage(),
    AlertPage(),
    SettingPage(),
  ];

  @override
  void initState() {
    super.initState();
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOut));

    _zonesSub = FirebaseService.allZonesStream().listen(_onZonesUpdate);
  }

  void _onZonesUpdate(List<Map<String, dynamic>> zones) {
    if (!mounted) return;

    final alertZones = zones.where((z) => z['isAlert'] == true).toList();
    final newKeys    = alertZones.map((z) => z['key'] as String).toSet();

    // zones that just became alert (weren't alerting before)
    final newAlerts = newKeys.difference(_prevAlertKeys);

    setState(() => _alertCount = alertZones.length);
    _prevAlertKeys = newKeys;

    if (newAlerts.isNotEmpty && _index != 2) {
      // find first new alert zone name
      final zoneName = alertZones
          .firstWhere((z) => newAlerts.contains(z['key']),
              orElse: () => alertZones.first)['zoneName'] as String;
      _showBanner('⚠ $zoneName เกินเกณฑ์! กดเพื่อดูรายละเอียด');
    }
  }

  void _showBanner(String text) {
    setState(() { _bannerText = text; _bannerVisible = true; });
    _bannerCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 4), _hideBanner);
  }

  void _hideBanner() {
    if (!mounted) return;
    _bannerCtrl.reverse().then((_) {
      if (mounted) setState(() => _bannerVisible = false);
    });
  }

  @override
  void dispose() {
    _zonesSub?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final navBg = isDark
        ? AppColors.darkSurface.withOpacity(0.95)
        : Colors.white.withOpacity(0.95);

    return Scaffold(
      body: Stack(children: [

        // ── Main content ────────────────────────────────────────────────────
        IndexedStack(index: _index, children: _pages),

        // ── Alert banner (slides from top) ──────────────────────────────────
        if (_bannerVisible)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: SlideTransition(
                position: _bannerSlide,
                child: GestureDetector(
                  onTap: () {
                    _hideBanner();
                    setState(() => _index = 2); // go to alert page
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                          color: AppColors.danger.withOpacity(0.4),
                          blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        _bannerText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      )),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white70, size: 20),
                    ]),
                  ),
                ),
              ),
            ),
          ),

      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: borderColor, width: 1)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(children: [
              _NavItem(icon: Icons.home_rounded,          label: 'หน้าหลัก',  index: 0, current: _index,
                  alertCount: 0,
                  onTap: (i) => setState(() => _index = i)),
              _NavItem(icon: Icons.bar_chart_rounded,     label: 'แดชบอร์ด',  index: 1, current: _index,
                  alertCount: 0,
                  onTap: (i) => setState(() => _index = i)),
              _NavItem(icon: Icons.notifications_rounded, label: 'แจ้งเตือน', index: 2, current: _index,
                  alertCount: _alertCount,
                  onTap: (i) => setState(() => _index = i)),
              _NavItem(icon: Icons.settings_rounded,      label: 'ตั้งค่า',   index: 3, current: _index,
                  alertCount: 0,
                  onTap: (i) => setState(() => _index = i)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, current, alertCount;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon, required this.label,
    required this.index, required this.current, required this.onTap,
    this.alertCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final color  = active ? AppColors.accent : AppColors.lightMuted;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, size: 22, color: color),
              if (alertCount > 0)
                Positioned(
                  top: -4, right: -6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        alertCount > 9 ? '9+' : '$alertCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.2),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
            if (active) ...[
              const SizedBox(height: 3),
              Container(width: 5, height: 5,
                  decoration: const BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle)),
            ],
          ]),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class SoundBar extends StatelessWidget {
  final double percent;
  final ZoneStatus status;
  const SoundBar({super.key, required this.percent, required this.status});

  List<Color> get _colors {
    switch (status) {
      case ZoneStatus.quiet:    return [const Color(0xFF34C97A), const Color(0xFF5DE89C)];
      case ZoneStatus.moderate: return [const Color(0xFFF5A623), const Color(0xFFFFC95C)];
      case ZoneStatus.loud:     return [const Color(0xFFF25F5C), const Color(0xFFFF8C8A)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: percent,
        minHeight: 8,
        backgroundColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        valueColor: AlwaysStoppedAnimation(_colors.first),
      ),
    );
  }
}

class ZoneCard extends StatelessWidget {
  final ZoneData zone;
  final VoidCallback? onTap;
  const ZoneCard({super.key, required this.zone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final cardColor   = isDark ? AppColors.darkCard   : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final mutedColor  = isDark ? AppColors.darkMuted  : AppColors.lightMuted;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: zone.statusBgColor,
                  borderRadius: BorderRadius.circular(10)),
              child: Center(child: Icon(zone.icon, size: 16, color: zone.statusColor)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone.name, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkText : AppColors.lightText)),
                Text(zone.location,
                    style: TextStyle(fontSize: 10, color: mutedColor)),
              ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: zone.statusBgColor,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(zone.statusLabel, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: zone.statusColor)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            RichText(text: TextSpan(children: [
              TextSpan(text: zone.db.toInt().toString(),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700,
                      color: zone.statusColor, height: 1)),
              TextSpan(text: ' dB',
                  style: TextStyle(fontSize: 11, color: mutedColor)),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoundBar(percent: zone.percent, status: zone.status),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0', style: TextStyle(fontSize: 9, color: mutedColor)),
                    Text('เกณฑ์ ${zone.threshold.toInt()}',
                        style: TextStyle(fontSize: 9, color: mutedColor)),
                    Text('100 dB', style: TextStyle(fontSize: 9, color: mutedColor)),
                  ]),
              ])),
          ]),
        ]),
      ),
    );
  }
}