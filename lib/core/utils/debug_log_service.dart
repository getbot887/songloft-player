import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';


/// 调试日志服务
///
/// 存储最近的调试日志，用于在设备上查看运行状态。
/// 单例模式，内存最大存储 200 条日志，同时写入本地文件。
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._();
  factory DebugLogService() => _instance;
  DebugLogService._();

  static const int _maxLogs = 200;
  static const String _logFileName = 'debug_logs.txt';

  final Queue<LogEntry> _logs = Queue<LogEntry>();

  /// 日志开关（默认开启）
  bool _enabled = true;

  /// 日志变化回调（用于 UI 刷新）
  VoidCallback? onLogAdded;

  /// 日志文件路径
  String? _logFilePath;

  /// 设置日志开关
  set enabled(bool value) => _enabled = value;

  /// 获取日志开关状态
  bool get isEnabled => _enabled;

  /// 初始化（获取日志文件路径）
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFilePath = '${dir.path}/$_logFileName';
      debugPrint('[DebugLog] 日志文件: $_logFilePath');
    } catch (e) {
      debugPrint('[DebugLog] 初始化失败: $e');
    }
  }

  /// 添加日志
  void log(String tag, String message) {
    // 日志开关关闭时，只输出到 debugPrint，不存储
    if (!_enabled) {
      debugPrint('[$tag] $message');
      return;
    }

    final entry = LogEntry(
      tag: tag,
      message: message,
      timestamp: DateTime.now(),
    );

    _logs.addLast(entry);

    // 超过最大数量时移除最旧的
    while (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }

    // 同时输出到 debugPrint
    debugPrint('[$tag] $message');

    // 写入本地文件
    _writeToFile(entry);

    onLogAdded?.call();
  }

  /// 写入日志到本地文件
  void _writeToFile(LogEntry entry) {
    if (_logFilePath == null) return;

    try {
      final file = File(_logFilePath!);
      file.writeAsStringSync(
        '${entry.toText()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('[DebugLog] 写入文件失败: $e');
    }
  }

  /// 获取所有日志（最新的在前）
  List<LogEntry> get logs => _logs.toList().reversed.toList();

  /// 获取指定 tag 的日志
  List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((e) => e.tag == tag).toList().reversed.toList();
  }

  /// 清空日志
  void clear() {
    _logs.clear();
    _clearFile();
    onLogAdded?.call();
  }

  /// 清空日志文件
  void _clearFile() {
    if (_logFilePath == null) return;
    try {
      final file = File(_logFilePath!);
      if (file.existsSync()) {
        file.writeAsStringSync('');
      }
    } catch (e) {
      debugPrint('[DebugLog] 清空文件失败: $e');
    }
  }

  /// 获取日志文件路径
  String? get logFilePath => _logFilePath;

  /// 获取日志文件内容
  Future<String> getLogFileContent() async {
    if (_logFilePath == null) return '';
    try {
      final file = File(_logFilePath!);
      if (file.existsSync()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('[DebugLog] 读取文件失败: $e');
    }
    return '';
  }

  /// 格式化日志为文本（用于导出）
  String toText({String? tag}) {
    final entries = tag != null ? getLogsByTag(tag) : logs;
    return entries.map((e) => e.toText()).join('\n');
  }

  /// 上传日志到服务端
  ///
  /// [logServerUrl] 日志服务地址，例如 https://log.uncooked.cloudns.org
  /// 返回上传结果消息
  Future<String> uploadLogs(String logServerUrl) async {
    if (_logFilePath == null) {
      return '日志文件路径未初始化';
    }

    final file = File(_logFilePath!);
    if (!file.existsSync()) {
      return '日志文件不存在';
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return '日志为空，无需上传';
    }

    // 移除末尾斜杠
    final baseUrl = logServerUrl.endsWith('/')
        ? logServerUrl.substring(0, logServerUrl.length - 1)
        : logServerUrl;

    try {
      final dio = Dio();
      // 日志服务器通常使用标准证书（如 Let's Encrypt），不强制自签 CA
      // 只有后端服务才需要 applyTrustedCertificate
      final response = await dio.post(
        '$baseUrl/api/debug-logs',
        data: {
          'logs': content,
          'timestamp': DateTime.now().toIso8601String(),
          'platform': Platform.operatingSystem,
        },
        options: Options(
          contentType: 'application/json',
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return '上传成功';
      } else {
        return '上传失败: HTTP ${response.statusCode}';
      }
    } on DioException catch (e) {
      return '上传失败: ${e.type} - ${e.message ?? e.error ?? "未知错误"}';
    } catch (e) {
      return '上传失败: $e';
    }
  }
}

/// 日志条目
class LogEntry {
  final String tag;
  final String message;
  final DateTime timestamp;

  const LogEntry({
    required this.tag,
    required this.message,
    required this.timestamp,
  });

  String toText() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '[$timeStr][$tag] $message';
  }
}
