import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// 蓝牙音频设备检测服务
///
/// 使用 audio_session 插件检测蓝牙音频设备（A2DP/SCO）的连接状态。
/// 当蓝牙设备连接/断开时，通过流通知监听者。
class BluetoothDetectionService {
  static final BluetoothDetectionService _instance = BluetoothDetectionService._();
  factory BluetoothDetectionService() => _instance;
  BluetoothDetectionService._();

  /// 蓝牙连接状态流控制器
  final _bluetoothConnectedController = StreamController<bool>.broadcast();

  /// 蓝牙连接状态流
  Stream<bool> get isBluetoothConnectedStream => _bluetoothConnectedController.stream;

  /// 当前是否蓝牙连接
  bool _isBluetoothConnected = false;
  bool get isBluetoothConnected => _isBluetoothConnected;

  bool _initialized = false;

  /// 初始化蓝牙检测服务
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // 监听音频设备变化
      session.devicesChangeStream.listen((devices) {
        final hasBluetooth = devices.output.any((d) =>
            d.type == AudioDeviceType.bluetoothA2dp ||
            d.type == AudioDeviceType.bluetoothSco);

        if (hasBluetooth != _isBluetoothConnected) {
          _isBluetoothConnected = hasBluetooth;
          _bluetoothConnectedController.add(hasBluetooth);
          debugPrint('[BluetoothDetection] 蓝牙状态变化: ${hasBluetooth ? "已连接" : "已断开"}');
        }
      });

      debugPrint('[BluetoothDetection] 初始化完成, 等待蓝牙设备连接事件');
      _initialized = true;
    } catch (e) {
      debugPrint('[BluetoothDetection] 初始化失败: $e');
    }
  }

  void dispose() {
    _bluetoothConnectedController.close();
  }
}
