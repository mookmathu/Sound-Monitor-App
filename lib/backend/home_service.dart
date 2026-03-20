import 'dart:convert';
import 'package:http/http.dart' as http;

class HomeService {
  static const String _baseUrl = 'https://api.netpie.io/v2/device';

  // Credentials ของ Mobile App (ใช้สำหรับ control)
  static const String _controlClientId = 'c652e620-6450-48a4-89e2-d6bfdf18fe95';
  static const String _controlToken    = 'XmsMZyBiFQDQFqurZHPWK5mtNVTmC2Vx';

  // Credentials ของ ESP32 (ใช้สำหรับอ่าน shadow)
  static const String _statusClientId = 'd0e6e9d1-ed49-4ddb-a8c1-ba74eb064706';
  static const String _statusToken    = 'UfUMSF4UvuE3sf7DYVtKeXh9sxCmrACJ';

  Map<String, String> get _controlHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Device $_controlClientId:$_controlToken',
  };

  Map<String, String> get _statusHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Device $_statusClientId:$_statusToken',
  };

  // ── อ่านสถานะจาก Device Shadow ──────────────────────────────────────────

  /// ดึงข้อมูลล่าสุดจาก Shadow ของ ESP32
  /// คืนค่า Map ที่มี db, loudCount, isAlert, zoneName
  Future<Map<String, dynamic>> getNoiseStatus() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/shadow/data'),
      headers: _statusHeaders,
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      final data = body['data'] as Map<String, dynamic>;
      return {
        'db':        (data['db'] as num?)?.toDouble() ?? 0.0,
        'loudCount': (data['loudCount'] as num?)?.toInt() ?? 0,
        'isAlert':   data['isAlert'] as bool? ?? false,
        'zoneName':  data['zoneName'] as String? ?? '',
      };
    } else {
      throw Exception('getNoiseStatus failed: ${response.statusCode}');
    }
  }

  // ── ส่งคำสั่งควบคุม ─────────────────────────────────────────────────────

  /// ส่งคำสั่ง RESET ให้ ESP32 ล้างการนับและปิด ALERT
  Future<void> sendReset() async {
    final payload = json.encode({
      'data': {'command': 'RESET'},
    });

    final response = await http.put(
      Uri.parse('$_baseUrl/message?topic=home/device_control'),
      headers: _controlHeaders,
      body: payload,
    );

    if (response.statusCode != 200) {
      throw Exception('sendReset failed: ${response.statusCode}');
    }
  }

  /// (legacy) ส่งค่าระดับเสียงเป็น double — เก็บไว้รองรับโค้ดเดิม
  Future<void> setSoundLevel(double level) async {
    final payload = json.encode({
      'data': {'sound_level': level},
    });

    final response = await http.put(
      Uri.parse('$_baseUrl/message?topic=home/device_control'),
      headers: _controlHeaders,
      body: payload,
    );

    if (response.statusCode != 200) {
      throw Exception('setSoundLevel failed: ${response.statusCode}');
    }
  }
}