import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 音频调试日志 - 用于排查蓝牙播放问题
/// 日志保存到手机：/Android/data/com.songloft.songloft_flutter/files/debug_logs/
class AudioDebugLogger {
  static final AudioDebugLogger _instance = AudioDebugLogger._();
  factory AudioDebugLogger() => _instance;
  AudioDebugLogger._();

  File? _logFile;
  bool _initialized = false;

  /// 初始化日志文件
  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/debug_logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final now = DateTime.now();
      final fileName = 'audio_${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}.log';
      _logFile = File('${logDir.path}/$fileName');
      _initialized = true;
      await write('=== 音频调试日志开始 ===');
      await write('时间: $now');
      await write('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      await write('========================');
    } catch (e) {
      debugPrint('[AudioDebugLogger] init failed: $e');
    }
  }

  /// 写入日志
  Future<void> write(String message) async {
    final now = DateTime.now();
    final timestamp = '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}.${_pad3(now.millisecond)}';
    final line = '[$timestamp] $message\n';
    
    debugPrint('[AudioLog] $message');
    
    final file = _logFile;
    if (file == null) return;
    
    try {
      await file.writeAsString(line, mode: FileMode.append);
    } catch (e) {
      debugPrint('[AudioDebugLogger] write failed: $e');
    }
  }

  /// 获取日志文件路径
  String? get logFilePath => _logFile?.path;

  /// 获取所有日志内容
  Future<String> readAll() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return '日志文件不存在';
    return file.readAsString();
  }

  /// 清空日志
  Future<void> clear() async {
    final file = _logFile;
    if (file == null) return;
    try {
      await file.writeAsString('');
      await write('=== 日志已清空 ===');
    } catch (e) {
      debugPrint('[AudioDebugLogger] clear failed: $e');
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _pad3(int n) => n.toString().padLeft(3, '0');
}
