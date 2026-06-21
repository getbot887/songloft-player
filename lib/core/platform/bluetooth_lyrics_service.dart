import 'package:audio_service/audio_service.dart';

/// 蓝牙车载歌词服务
///
/// 通过 audio_service 的 MediaItem.extras 机制，
/// 将歌词写入 MediaSession 的 MediaMetadata，
/// 经由蓝牙 AVRCP 协议发送到车机显示屏。
///
/// 支持两种模式：
/// - 标准模式：在 extras 中写入 METADATA_KEY_lyrics（需车机 AVRCP 1.6+）
/// - 兼容模式：将歌词替换歌名显示（适用于老旧车机）
class BluetoothLyricsService {
  static final BluetoothLyricsService _instance = BluetoothLyricsService._();
  factory BluetoothLyricsService() => _instance;
  BluetoothLyricsService._();

  /// MediaMetadata.METADATA_KEY_lyrics 的字符串值（API 30+）
  static const _metadataKeyLyrics = 'android.media.metadata.LYRICS';

  /// audio_handler 引用，用于访问 mediaItem 流
  BaseAudioHandler? _handler;

  /// 当前正在播放的原始 MediaItem（不含歌词修改）
  MediaItem? _originalMediaItem;

  /// 上一次发送的歌词文本（用于标准模式去重）
  String? _lastLyrics;

  /// 初始化，传入 audio_handler
  void init(BaseAudioHandler handler) {
    _handler = handler;
  }

  /// 发送歌词到车机
  ///
  /// [lyrics] 当前歌词行文本
  /// [title] 原始歌名
  /// [artist] 原始歌手
  /// [compatMode] 是否使用兼容模式（障眼法）
  Future<void> updateLyrics({
    required String lyrics,
    required String title,
    required String artist,
    bool compatMode = false,
  }) async {
    final handler = _handler;
    if (handler == null) return;

    final current = handler.mediaItem.value;
    if (current == null) return;

    // 保存原始 MediaItem（首次）
    _originalMediaItem ??= current;

    if (compatMode) {
      // 兼容模式：替换 title/artist
      MediaItem spoofed;
      if (lyrics.isNotEmpty) {
        // 歌手字段改为 "原歌名 - 原歌手"
        final originalInfo = StringBuffer();
        if (title.isNotEmpty) originalInfo.write(title);
        if (artist.isNotEmpty) {
          if (originalInfo.isNotEmpty) originalInfo.write(' - ');
          originalInfo.write(artist);
        }
        spoofed = current.copyWith(
          title: lyrics,
          artist: originalInfo.toString(),
        );
      } else {
        // 空歌词时恢复原始歌名
        spoofed = current.copyWith(
          title: _originalMediaItem?.title ?? title,
          artist: _originalMediaItem?.artist ?? artist,
        );
      }
      handler.mediaItem.add(spoofed);
    } else {
      // 标准模式：在 extras 中写入歌词
      if (lyrics == _lastLyrics) return;
      _lastLyrics = lyrics;

      final extras = Map<String, dynamic>.from(current.extras ?? {});
      if (lyrics.isNotEmpty) {
        extras[_metadataKeyLyrics] = lyrics;
      } else {
        extras.remove(_metadataKeyLyrics);
      }
      final updated = current.copyWith(extras: extras);
      handler.mediaItem.add(updated);
    }
  }

  /// 恢复原始歌曲元数据
  ///
  /// 在蓝牙断开、歌曲切换、功能关闭时调用
  Future<void> restoreMetadata() async {
    final handler = _handler;
    if (handler == null) return;

    final original = _originalMediaItem;
    if (original != null) {
      handler.mediaItem.add(original);
    }
    _lastLyrics = null;
  }

  /// 歌曲切换时重置状态
  ///
  /// 在播放新歌时调用，清除上一首的缓存
  void onSongChanged() {
    _originalMediaItem = null;
    _lastLyrics = null;
  }

  /// 重置状态（功能关闭时调用）
  void reset() {
    _originalMediaItem = null;
    _lastLyrics = null;
  }
}
