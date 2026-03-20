import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final String clientId;
  final String token;
  final String secret;

  /// Callback เมื่อได้รับข้อมูลใหม่จาก ESP32
  final void Function({
    required double db,
    required int loudCount,
    required bool isAlert,
    required String zoneName,
  }) onDataReceived;

  late MqttServerClient _client;

  MqttService({
    required this.clientId,
    required this.token,
    required this.secret,
    required this.onDataReceived,
  });

  Future<void> connect() async {
    _client = MqttServerClient('broker.netpie.io', clientId);
    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(token, secret)
        .startClean();

    try {
      await _client.connect();
    } catch (e) {
      print('MQTT connect error: $e');
      _client.disconnect();
      return;
    }

    if (_client.connectionStatus!.state == MqttConnectionState.connected) {
      // Topic ที่ ESP32 publish ข้อมูลมา
      _client.subscribe('@msg/home/device_status', MqttQos.atMostOnce);
      _client.updates!.listen(_onMessage);
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    final recMsg = events[0].payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(
      recMsg.payload.message,
    );

    try {
      final decoded = json.decode(payload);
      final data = decoded['data'];

      // ESP32 ส่งมาในรูปแบบ:
      // { "data": { "db": 62.5, "loudCount": 2, "isAlert": false, "zoneName": "Board Game Room" } }
      final double db         = (data['db'] as num).toDouble();
      final int loudCount     = (data['loudCount'] as num).toInt();
      final bool isAlert      = data['isAlert'] as bool;
      final String zoneName   = data['zoneName'] as String? ?? '';

      onDataReceived(
        db: db,
        loudCount: loudCount,
        isAlert: isAlert,
        zoneName: zoneName,
      );
    } catch (e) {
      print('MQTT parse error: $e  payload: $payload');
    }
  }

  /// ส่งคำสั่ง RESET ไปยัง ESP32
  void sendReset() {
    if (_client.connectionStatus?.state != MqttConnectionState.connected) return;

    final payload = json.encode({'command': 'RESET'});
    final builder = MqttClientPayloadBuilder()..addString(payload);

    _client.publishMessage(
      '@msg/home/device_control',
      MqttQos.atMostOnce,
      builder.payload!,
    );
    print('MQTT → RESET sent');
  }

  void _onConnected()    => print('MQTT Connected');
  void _onDisconnected() => print('MQTT Disconnected');

  void disconnect() => _client.disconnect();
}