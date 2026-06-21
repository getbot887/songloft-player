import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 蓝牙歌词模式常量
class BluetoothLyricsMode {
  static const off = 'off';
  static const lyricsScreenOnly = 'lyrics_screen_only';
  static const always = 'always';
  static const specificDevice = 'specific_device';
  static const force = 'force';
}

/// 蓝牙音频设备检测服务
///
/// 通过 MethodChannel 检测蓝牙音频设备连接状态。
class BluetoothDetectionService {
  static final BluetoothDetectionService _instance = BluetoothDetectionService._();
  factory BluetoothDetectionService() => _instance;
  BluetoothDetectionService._();

  static const _channel = MethodChannel('com.songloft/bluetooth_detection');

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
      // 设置回调，接收原生端的蓝牙状态变化通知
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onBluetoothStateChanged') {
          final connected = call.arguments as bool? ?? false;
          if (connected != _isBluetoothConnected) {
            _isBluetoothConnected = connected;
            _bluetoothConnectedController.add(connected);
            debugPrint('[BluetoothDetection] 蓝牙状态变化: ${connected ? "已连接" : "已断开"}');
          }
        }
      });

      // 查询初始蓝牙状态
      final result = await _channel.invokeMethod<bool>('isBluetoothConnected');
      _isBluetoothConnected = result ?? false;

      debugPrint('[BluetoothDetection] 初始化完成, 蓝牙状态: ${_isBluetoothConnected ? "已连接" : "未连接"}');
      _initialized = true;
    } catch (e) {
      debugPrint('[BluetoothDetection] 初始化失败: $e');
    }
  }

  /// 获取当前已连接的蓝牙音频设备名称列表
  Future<List<String>> getConnectedDeviceNames() async {
    if (!_isBluetoothConnected) return const [];
    try {
      final result = await _channel.invokeMethod<List>('getConnectedDeviceNames');
      return result?.cast<String>() ?? const [];
    } catch (e) {
      debugPrint('[BluetoothDetection] 获取设备名称失败: $e');
      return const [];
    }
  }

  /// 判断当前是否应该推送蓝牙歌词
  ///
  /// [mode] 模式：off / lyrics_screen_only / always / specific_device / force
  /// [deviceNames] 用户设置的设备名列表（specific_device 模式用）
  /// [isLyricsScreenOpen] 是否在歌词界面（lyrics_screen_only 模式用）
  Future<bool> shouldPushLyrics({
    required String mode,
    required List<String> deviceNames,
    bool isLyricsScreenOpen = false,
  }) async {
    switch (mode) {
      case BluetoothLyricsMode.off:
        return false;
      case BluetoothLyricsMode.lyricsScreenOnly:
        if (!isLyricsScreenOpen) return false;
        return _isBluetoothConnected;
      case BluetoothLyricsMode.always:
        return _isBluetoothConnected;
      case BluetoothLyricsMode.specificDevice:
        if (!_isBluetoothConnected) return false;
        if (deviceNames.isEmpty) return false;
        final connectedNames = await getConnectedDeviceNames();
        return connectedNames.any((c) =>
            deviceNames.any((t) => c.toLowerCase().contains(t.trim().toLowerCase())));
      case BluetoothLyricsMode.force:
        return true;
      default:
        return false;
    }
  }

  void dispose() {
    _bluetoothConnectedController.close();
  }
}
