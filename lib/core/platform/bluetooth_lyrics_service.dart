import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/debug_log_service.dart';

/// 蓝牙车载歌词服务
///
/// 通过 MethodChannel 与 Android 原生层通信，
/// 将歌词写入 MediaSession 的 MediaMetadata，
/// 经由蓝牙 AVRCP 协议发送到车机显示屏。
///
/// 支持两种模式：
/// - 标准模式：写入 METADATA_KEY_lyrics（需车机 AVRCP 1.6+）
/// - 兼容模式：将歌词替换歌名显示（适用于老旧车机）
class BluetoothLyricsService {
  static final BluetoothLyricsService _instance = BluetoothLyricsService._();
  factory BluetoothLyricsService() => _instance;
  BluetoothLyricsService._();

  static const _channel = MethodChannel('com.songloft/bluetooth_lyrics');
  final DebugLogService _log = DebugLogService();

  bool get _isApplicable => !kIsWeb && Platform.isAndroid;

  /// 上一次发送的歌词文本（用于去重）
  String? _lastLyrics;

  /// 蓝牙断开回调（由调用方设置）
  VoidCallback? onBluetoothDisconnected;

  /// 初始化，监听原生端的蓝牙断开事件
  void init() {
    if (!_isApplicable) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBluetoothDisconnected') {
        _lastLyrics = null;
        onBluetoothDisconnected?.call();
      }
    });
  }

  /// 发送歌词到车机
  ///
  /// [lyrics] 当前歌词行文本
  /// [title] 原始歌名
  /// [artist] 原始歌手
  /// [album] 原始专辑
  /// [artUri] 封面 URL
  /// [duration] 歌曲时长（毫秒）
  /// [compatMode] 是否使用兼容模式（障眼法）
  Future<void> updateLyrics({
    required String lyrics,
    required String title,
    required String artist,
    String album = '',
    String artUri = '',
    int duration = 0,
    bool compatMode = false,
  }) async {
    if (!_isApplicable) {
      _log.log('BTLyrics', '跳过: 非 Android 平台');
      return;
    }

    // 兼容模式下不做过滤（需要刷新空格技巧）
    if (!compatMode && lyrics == _lastLyrics) return;

    _lastLyrics = lyrics;

    // 兼容模式下，如果歌词为空，发送空字符串让原生端恢复歌名
    final effectiveLyrics = lyrics;

    try {
      _log.log('BTLyrics', '推送歌词: "$effectiveLyrics", title=$title, compatMode=$compatMode');
      await _channel.invokeMethod('updateLyrics', {
        'lyrics': effectiveLyrics,
        'title': title,
        'artist': artist,
        'album': album,
        'artUri': artUri,
        'duration': duration,
        'compatMode': compatMode,
      });
      _log.log('BTLyrics', '推送成功');
    } catch (e) {
      _log.log('BTLyrics', '推送失败: $e');
    }
  }

  /// 恢复原始歌曲元数据
  ///
  /// 在蓝牙断开、歌曲切换、功能关闭时调用
  Future<void> restoreMetadata() async {
    if (!_isApplicable) return;
    _lastLyrics = null;
    try {
      await _channel.invokeMethod('restoreMetadata');
    } catch (e) {
      debugPrint('[BluetoothLyrics] restoreMetadata failed: $e');
    }
  }

  /// 歌曲切换时更新原始元数据缓存
  ///
  /// 在播放新歌时调用，确保原生端缓存的是新歌的信息
  Future<void> updateSongInfo({
    required String title,
    required String artist,
    String album = '',
    String artUri = '',
    int duration = 0,
  }) async {
    if (!_isApplicable) return;
    _lastLyrics = null;
    try {
      await _channel.invokeMethod('updateSongInfo', {
        'title': title,
        'artist': artist,
        'album': album,
        'artUri': artUri,
        'duration': duration,
      });
    } catch (e) {
      debugPrint('[BluetoothLyrics] updateSongInfo failed: $e');
    }
  }

  /// 重置状态（功能关闭时调用）
  void reset() {
    _lastLyrics = null;
  }
}
