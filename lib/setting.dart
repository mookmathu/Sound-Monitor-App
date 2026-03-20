import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';
import 'backend/firebase_service.dart';

// ── App info constants ────────────────────────────────────────────────────────
const _kAppVersion   = '1.4.2';
const _kBuildNumber  = '42';
const _kReleaseDate  = '10 มีนาคม 2568';
const _kOrganization = 'ห้องสมุดมหาวิทยาลัย';
const _kDevelopers   = [
  _Developer(name: 'นางสาว มธุรดา มีปาน 6621604874',      role: 'Lead Developer'),
  _Developer(name: 'นางสาว ปริศนา คำมี 6621601026',        role: 'UI / UX Design'),
  _Developer(name: 'นางสาว นุสนีย์ มะแอเคียน 6621604831',  role: 'Hardware & IoT'),
];

class _Developer {
  final String name, role;
  const _Developer({required this.name, required this.role});
}

class _Lang {
  final String code, label, flag;
  const _Lang({required this.code, required this.label, required this.flag});
}

const _kLanguages = [
  _Lang(code: 'th', label: 'ภาษาไทย', flag: 'TH'),
];

// ─────────────────────────────────────────────────────────────────────────────

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

// ไม่ใช้ TickerProviderStateMixin เพราะไม่มี TabController แล้ว
class _SettingPageState extends State<SettingPage> {

  List<Map<String, dynamic>> _zones   = [];
  StreamSubscription?        _zonesSub;

  bool   _nightMode    = false;
  String _langCode     = 'th';
  int    _selectedZone = 0; // index ของโซนที่เลือก

  @override
  void initState() {
    super.initState();
    _zonesSub = FirebaseService.allZonesStream().listen((zones) {
      if (mounted) {
        setState(() {
          _zones = zones;
          if (_selectedZone >= zones.length && zones.isNotEmpty) {
            _selectedZone = zones.length - 1;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _zonesSub?.cancel();
    super.dispose();
  }

  void _showSnack(String msg, Color color, IconData icon) {
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
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final textColor   = isDark ? AppColors.darkText   : AppColors.lightText;
    final mutedColor  = isDark ? AppColors.darkMuted  : AppColors.lightMuted;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardColor   = isDark ? AppColors.darkCard   : AppColors.lightCard;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [

          // ── HEADER ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ตั้งค่า', style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700,
                      color: textColor)),
                  Text('ปรับแต่งการทำงานของระบบ',
                      style: TextStyle(fontSize: 11, color: mutedColor)),
                ]),
            ),
          ),

          // ══════════════════════════════════════════════════════════════════
          // 1. เกณฑ์ระดับเสียงแยกโซน
          // ══════════════════════════════════════════════════════════════════
          _SecLabel('เกณฑ์ระดับเสียงแต่ละโซน', mutedColor),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _zones.isEmpty
                  ? _Card(isDark: isDark, child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(children: [
                        Icon(Icons.sensors_off_rounded,
                            color: mutedColor, size: 16),
                        const SizedBox(width: 8),
                        Text('รอโหลดข้อมูลโซน...',
                            style: TextStyle(fontSize: 13, color: mutedColor)),
                      ]),
                    ))
                  : Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                        boxShadow: [BoxShadow(
                            color: Colors.black
                                .withOpacity(isDark ? 0.25 : 0.05),
                            blurRadius: 10)],
                      ),
                      child: Column(children: [

                        // ── header ──────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                          child: Row(children: [
                            Icon(Icons.tune_rounded,
                                size: 15, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Text('เลือกโซนที่ต้องการตั้งค่า',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textColor)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accentBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${_zones.length} โซน',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent)),
                            ),
                          ]),
                        ),

                        // ── zone chip selector (horizontal scroll) ─────────
                        SizedBox(
                          height: 38,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            itemCount: _zones.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final z       = _zones[i];
                              final active  = _selectedZone == i;
                              final isAlert =
                                  z['isAlert'] as bool? ?? false;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedZone = i),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.accent
                                        : (isDark
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    boxShadow: active
                                        ? [BoxShadow(
                                            color: AppColors.accent
                                                .withOpacity(0.3),
                                            blurRadius: 8,
                                            offset:
                                                const Offset(0, 2))]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isAlert) ...[
                                        Icon(Icons.warning_rounded,
                                            size: 11,
                                            color: active
                                                ? Colors.white
                                                : AppColors.danger),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        z['zoneName'] as String,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: active
                                                ? Colors.white
                                                : mutedColor),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 8),
                        Divider(height: 1, indent: 12,
                            endIndent: 12, color: borderColor),

                        // ── zone detail panel ──────────────────────────────
                        if (_selectedZone < _zones.length)
                          _ZoneThresholdPanel(
                            key: ValueKey(
                                _zones[_selectedZone]['key']),
                            zoneKey: _zones[_selectedZone]['key']
                                as String,
                            name: _zones[_selectedZone]['zoneName']
                                as String,
                            value: (_zones[_selectedZone]['threshold'] ??
                                    40)
                                .toDouble(),
                            db: (_zones[_selectedZone]['db'] as num?)
                                    ?.toDouble() ??
                                0,
                            isAlert: _zones[_selectedZone]['isAlert']
                                    as bool? ??
                                false,
                            isDark: isDark,
                          ),
                      ]),
                    ),
            ),
          ),

          // ══════════════════════════════════════════════════════════════════
          // 2. การตั้งค่าทั่วไป
          // ══════════════════════════════════════════════════════════════════
          _SecLabel('การตั้งค่าทั่วไป', mutedColor),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Card(isDark: isDark, child: Column(children: [
                _IconSwitchTile(
                  icon: Icons.nightlight_round,
                  iconBg: AppColors.accentBg,
                  iconColor: AppColors.accent,
                  title: 'โหมดกลางคืน',
                  subtitle: 'เปลี่ยน theme เป็น dark',
                  value: _nightMode,
                  borderColor: borderColor,
                  isLast: true,
                  onChanged: (v) {
                    setState(() => _nightMode = v);
                    MyApp.of(context)?.setTheme(v);
                  },
                ),
              ])),
            ),
          ),

          // ══════════════════════════════════════════════════════════════════
          // 3. ภาษา / Language
          // ══════════════════════════════════════════════════════════════════
          _SecLabel('ภาษา / Language', mutedColor),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Card(
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.language_rounded,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text('เลือกภาษาที่ใช้แสดงผล',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textColor)),
                      ]),
                      const SizedBox(height: 12),
                      Row(
                        children: _kLanguages.map((lang) {
                          final active = _langCode == lang.code;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4),
                              child: GestureDetector(
                                onTap: () {
                                  setState(
                                      () => _langCode = lang.code);
                                  _showSnack(
                                      'เปลี่ยนภาษาเป็น ${lang.label}',
                                      AppColors.accent,
                                      Icons.check_circle_rounded);
                                },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.accent
                                        : (isDark
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    boxShadow: active
                                        ? [BoxShadow(
                                            color: AppColors.accent
                                                .withOpacity(0.3),
                                            blurRadius: 8,
                                            offset:
                                                const Offset(0, 3))]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: active
                                              ? Colors.white
                                                  .withOpacity(0.25)
                                              : (isDark
                                                  ? AppColors.darkCard
                                                  : Colors.white),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(lang.flag,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: active
                                                    ? Colors.white
                                                    : AppColors.accent)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(lang.label,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: active
                                                  ? Colors.white
                                                  : textColor)),
                                      if (active) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.check_rounded,
                                            size: 14,
                                            color: Colors.white),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ภาษาที่ใช้อยู่: '
                        '${_kLanguages.firstWhere((l) => l.code == _langCode).label}',
                        style: TextStyle(fontSize: 10, color: mutedColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ══════════════════════════════════════════════════════════════════
          // 4. เกี่ยวกับแอปพลิเคชัน
          // ══════════════════════════════════════════════════════════════════
          _SecLabel('เกี่ยวกับแอปพลิเคชัน', mutedColor),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Card(isDark: isDark, child: Column(children: [

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, Color(0xFF7EB0FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: AppColors.accent.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))],
                      ),
                      child: const Center(
                          child: Icon(Icons.graphic_eq_rounded,
                              color: Colors.white, size: 28)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Library Sound Monitor',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textColor)),
                        const SizedBox(height: 2),
                        Text(_kOrganization,
                            style: TextStyle(
                                fontSize: 11, color: mutedColor)),
                      ],
                    )),
                  ]),
                ),

                Divider(height: 1, indent: 14, endIndent: 14,
                    color: borderColor),

                _InfoRow(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.accent,
                  iconBg: AppColors.accentBg,
                  label: 'เวอร์ชัน',
                  value: 'v$_kAppVersion (Build $_kBuildNumber)',
                  borderColor: borderColor,
                  textColor: textColor,
                  mutedColor: mutedColor,
                ),
                _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  iconColor: AppColors.teal,
                  iconBg: AppColors.tealBg,
                  label: 'วันที่อัปเดต',
                  value: _kReleaseDate,
                  borderColor: borderColor,
                  textColor: textColor,
                  mutedColor: mutedColor,
                ),

                Divider(height: 1, indent: 14, endIndent: 14,
                    color: borderColor),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Icon(Icons.people_rounded,
                        size: 15, color: mutedColor),
                    const SizedBox(width: 6),
                    Text('ผู้จัดทำ',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                            letterSpacing: 1.2)),
                  ]),
                ),

                ..._kDevelopers.asMap().entries.map((e) {
                  final dev    = e.value;
                  final isLast = e.key == _kDevelopers.length - 1;
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                              child: Icon(Icons.person_rounded,
                                  size: 18, color: mutedColor)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dev.name,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColor)),
                            Text(dev.role,
                                style: TextStyle(
                                    fontSize: 10, color: mutedColor)),
                          ],
                        )),
                      ]),
                    ),
                    if (!isLast)
                      Divider(height: 1, indent: 14, endIndent: 14,
                          color: borderColor),
                  ]);
                }),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Wrap(spacing: 6, runSpacing: 6, children: const [
                    _TechBadge('Flutter', Icons.flutter_dash,
                        AppColors.accent, AppColors.accentBg),
                    _TechBadge('Firebase',
                        Icons.local_fire_department_rounded,
                        AppColors.warn, AppColors.warnBg),
                    _TechBadge('ESP32',
                        Icons.developer_board_rounded,
                        AppColors.teal, AppColors.tealBg),
                    _TechBadge('MQTT', Icons.wifi_rounded,
                        AppColors.safe, AppColors.safeBg),
                  ]),
                ),

              ])),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),

        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Zone Threshold Panel
// ─────────────────────────────────────────────────────────────────────────────
class _ZoneThresholdPanel extends StatefulWidget {
  final String zoneKey, name;
  final double value, db;
  final bool isAlert, isDark;

  const _ZoneThresholdPanel({
    super.key,
    required this.zoneKey,
    required this.name,
    required this.value,
    required this.db,
    required this.isAlert,
    required this.isDark,
  });

  @override
  State<_ZoneThresholdPanel> createState() => _ZoneThresholdPanelState();
}

class _ZoneThresholdPanelState extends State<_ZoneThresholdPanel> {
  late double _value;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(_ZoneThresholdPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isDragging) {
      setState(() => _value = widget.value);
    }
  }

  Color get _thresholdColor {
    if (_value >= 70) return AppColors.danger;
    if (_value >= 50) return AppColors.warn;
    return AppColors.safe;
  }

  Color get _liveColor {
    if (widget.db >= _value) return AppColors.danger;
    if (widget.db >= _value * 0.8) return AppColors.warn;
    return AppColors.safe;
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = widget.isDark;
    final textColor  = isDark ? AppColors.darkText  : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    final trackBg    = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Live dB + status ──────────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _liveColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _liveColor.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.graphic_eq_rounded, size: 12, color: _liveColor),
              const SizedBox(width: 5),
              Text('${widget.db.toStringAsFixed(0)} dB ขณะนี้',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _liveColor)),
            ]),
          ),
          const Spacer(),
          if (widget.isAlert)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_rounded,
                    size: 11, color: AppColors.danger),
                SizedBox(width: 4),
                Text('กำลังแจ้งเตือน',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger)),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.safeBg,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded,
                    size: 11, color: AppColors.safe),
                SizedBox(width: 4),
                Text('ปกติ',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.safe)),
              ]),
            ),
        ]),

        const SizedBox(height: 16),

        // ── Threshold label + value ────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('เกณฑ์เสียงของโซนนี้',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            Text('เลื่อนเพื่อปรับ',
                style: TextStyle(fontSize: 10, color: mutedColor)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _thresholdColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${_value.toInt()} dB',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _thresholdColor)),
          ),
        ]),

        // ── Slider ────────────────────────────────────────────────────────
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _thresholdColor,
            inactiveTrackColor: trackBg,
            thumbColor: Colors.white,
            overlayColor: _thresholdColor.withOpacity(0.15),
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 9),
            trackHeight: 6,
          ),
          child: Slider(
            value: _value,
            min: 20,
            max: 100,
            divisions: 80,
            label: '${_value.toInt()} dB',
            onChangeStart: (_) => setState(() => _isDragging = true),
            onChanged: (v) => setState(() => _value = v),
            onChangeEnd: (v) {
              setState(() => _isDragging = false);
              FirebaseService.updateZoneThreshold(
                  widget.zoneKey, v.roundToDouble());
            },
          ),
        ),

        // ── Scale labels ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('20 dB',
                  style: TextStyle(fontSize: 9, color: mutedColor)),
              Text('60 dB',
                  style: TextStyle(fontSize: 9, color: mutedColor)),
              Text('100 dB',
                  style: TextStyle(fontSize: 9, color: mutedColor)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SecLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SecLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5)),
    ),
  );
}

class _Card extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _Card({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
          color:
              isDark ? AppColors.darkBorder : AppColors.lightBorder),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
          blurRadius: 10)],
    ),
    child: child,
  );
}

class _IconSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor, borderColor;
  final String title, subtitle;
  final bool value, isLast;
  final ValueChanged<bool> onChanged;

  const _IconSwitchTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.borderColor,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final textColor  = isDark ? AppColors.darkText  : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10)),
          child: Center(child: Icon(icon, size: 17, color: iconColor)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor)),
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: mutedColor)),
          ],
        )),
        Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg, borderColor, textColor, mutedColor;
  final String label, value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8)),
          child: Center(child: Icon(icon, size: 15, color: iconColor)),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(fontSize: 13, color: mutedColor)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor)),
      ]),
    ),
    Divider(height: 1, indent: 14, endIndent: 14, color: borderColor),
  ]);
}

class _TechBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color, bg;
  const _TechBadge(this.label, this.icon, this.color, this.bg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    ]),
  );
}