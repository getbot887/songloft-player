import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/audio_service.dart';
import '../utils/debug_log_service.dart';

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
  final DebugLogService _log = DebugLogService();

  /// 蓝牙连接状态流控制器
  final _bluetoothConnectedController = StreamController<bool>.broadcast();

  /// 蓝牙连接状态流
  Stream<bool> get isBluetoothConnectedStream => _bluetoothConnectedController.stream;

  /// 蓝牙连接事件回调（由 PlayerNotifier 注入，用于自动播放检查）
  void Function(bool connected, String deviceName)? onBtConnectionChanged;

  /// 当前是否蓝牙连接
  bool _isBluetoothConnected = false;
  bool get isBluetoothConnected => _isBluetoothConnected;

  bool _initialized = false;

  /// 初始化蓝牙检测服务
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb || !Platform.isAndroid) {
      _log.log('BT', '跳过初始化: 非 Android 平台');
      return;
    }

    try {
      // 设置回调，接收原生端的蓝牙状态变化通知
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onBluetoothStateChanged':
            final connected = call.arguments as bool? ?? false;
            if (connected != _isBluetoothConnected) {
              _isBluetoothConnected = connected;
              _bluetoothConnectedController.add(connected);
              if (connected) {
                final names = await getConnectedDeviceNames();
                final deviceName = names.isNotEmpty ? names.first : '未知设备';
                SongloftAudioHandler.connectedBtDevice = deviceName;
                _log.log('BT', '蓝牙已连接: $deviceName');
                onBtConnectionChanged?.call(true, deviceName);
              } else {
                SongloftAudioHandler.connectedBtDevice = '无';
                _log.log('BT', '蓝牙已断开');
                onBtConnectionChanged?.call(false, '无');
              }
            }
            break;
          case 'onLog':
            // 原生日志转发到 DebugLogService
            final args = call.arguments as Map? ?? {};
            final tag = args['tag'] as String? ?? 'Native';
            final message = args['message'] as String? ?? '';
            _log.log(tag, message);
            break;
        }
      });

      // 查询初始蓝牙状态
      final result = await _channel.invokeMethod<bool>('isBluetoothConnected');
      _isBluetoothConnected = result ?? false;

      // 如果蓝牙已连接，查询设备名称（启动时已经连接的场景）
      if (_isBluetoothConnected) {
        final names = await getConnectedDeviceNames();
        final deviceName = names.isNotEmpty ? names.first : '未知设备';
        SongloftAudioHandler.connectedBtDevice = deviceName;
        _log.log('BT', '初始化完成, 蓝牙已连接, 设备: $deviceName');
      } else {
        SongloftAudioHandler.connectedBtDevice = '无';
        _log.log('BT', '初始化完成, 蓝牙未连接');
      }
      _initialized = true;
    } catch (e) {
      _log.log('BT', '初始化失败: $e');
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
    bool result;
    switch (mode) {
      case BluetoothLyricsMode.off:
        result = false;
        break;
      case BluetoothLyricsMode.lyricsScreenOnly:
        if (!isLyricsScreenOpen) {
          _log.log('BT', 'lyricsScreenOnly: 歌词页未打开');
          return false;
        }
        result = _isBluetoothConnected;
        break;
      case BluetoothLyricsMode.always:
        result = _isBluetoothConnected;
        break;
      case BluetoothLyricsMode.specificDevice:
        if (!_isBluetoothConnected) {
          _log.log('BT', 'specificDevice: 蓝牙未连接');
          return false;
        }
        if (deviceNames.isEmpty) {
          _log.log('BT', 'specificDevice: 未设置设备名');
          return false;
        }
        final connectedNames = await getConnectedDeviceNames();
        _log.log('BT', 'specificDevice: 已连接设备=$connectedNames, 目标设备=$deviceNames');
        result = connectedNames.any((c) =>
            deviceNames.any((t) => c.toLowerCase().contains(t.trim().toLowerCase())));
        break;
      case BluetoothLyricsMode.force:
        result = true;
        break;
      default:
        result = false;
    }
    _log.log('BT', 'shouldPushLyrics: mode=$mode, result=$result');
    return result;
  }

  void dispose() {
    _bluetoothConnectedController.close();
  }
}
