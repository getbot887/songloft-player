import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/bluetooth_lyrics_service.dart';
import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/lyric_parser.dart';
import 'player_provider.dart';

/// 蓝牙歌词状态
class BluetoothLyricsState {
  final List<LyricLine> lyrics;
  final int currentIndex;

  const BluetoothLyricsState({
    this.lyrics = const [],
    this.currentIndex = -1,
  });

  BluetoothLyricsState copyWith({
    List<LyricLine>? lyrics,
    int? currentIndex,
  }) {
    return BluetoothLyricsState(
      lyrics: lyrics ?? this.lyrics,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

/// 蓝牙歌词 Provider
///
/// 强制推送模式：始终推送歌词到车机，不依赖蓝牙检测。
final bluetoothLyricsProvider =
    NotifierProvider<BluetoothLyricsNotifier, BluetoothLyricsState>(
  BluetoothLyricsNotifier.new,
);

class BluetoothLyricsNotifier extends Notifier<BluetoothLyricsState> {
  String? _lastLoadedLyricUrl;
  final BluetoothLyricsService _btLyrics = BluetoothLyricsService();

  @override
  BluetoothLyricsState build() {
    // 监听当前歌曲变化
    ref.listen(playerStateProvider.select((s) => s.currentSong), (prev, next) {
      // 通知原生端更新缓存的元数据
      _btLyrics.updateSongInfo(
        title: next?.title ?? '',
        artist: next?.artist ?? '',
        album: next?.album ?? '',
      );
      _loadLyrics(next?.lyricUrl);
    });

    // 监听播放进度变化
    ref.listen(playerStateProvider.select((s) => s.currentTime), (prev, next) {
      _updateCurrentLine(next);
    });

    return const BluetoothLyricsState();
  }

  /// 加载歌词
  Future<void> _loadLyrics(String? lyricUrl) async {
    if (lyricUrl == null || lyricUrl.isEmpty) {
      _lastLoadedLyricUrl = null;
      state = state.copyWith(lyrics: [], currentIndex: -1);
      return;
    }

    if (_lastLoadedLyricUrl == lyricUrl && state.lyrics.isNotEmpty) return;

    state = state.copyWith(lyrics: [], currentIndex: -1);

    // 先尝试缓存
    final cached = await LyricCacheService().get(lyricUrl);
    if (cached != null) {
      _lastLoadedLyricUrl = lyricUrl;
      final lyrics = LyricParser.parse(cached);
      state = state.copyWith(lyrics: lyrics);
      return;
    }

    // 从网络加载
    try {
      final fullUrl = UrlHelper.buildLyricUrl(lyricUrl);
      final response = await Dio().get<Map<String, dynamic>>(fullUrl);

      String lyricText = '';
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final main = body['lyric'];
        if (main is String) lyricText = main;
      }

      _lastLoadedLyricUrl = lyricUrl;
      final lyrics = LyricParser.parse(lyricText);
      state = state.copyWith(lyrics: lyrics);

      if (lyricText.isNotEmpty) {
        await LyricCacheService().put(lyricUrl, lyricText);
      }
    } catch (e) {
      debugPrint('[BluetoothLyrics] 加载歌词失败: $e');
    }
  }

  /// 更新当前歌词行
  void _updateCurrentLine(Duration position) {
    if (state.lyrics.isEmpty) return;

    final newIndex = LyricParser.findCurrentLine(state.lyrics, position);
    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);
      _sendLyricsToBluetooth();
    }
  }

  /// 发送歌词到蓝牙
  void _sendLyricsToBluetooth() async {
    // 检查开关是否开启
    final prefs = await ref.read(appPreferencesProvider.future);
    final enabled = prefs.getBluetoothLyricsEnabled();
    if (!enabled) return;

    final song = ref.read(playerStateProvider).currentSong;
    if (song == null) return;

    final lyrics = state.currentIndex >= 0 && state.currentIndex < state.lyrics.length
        ? state.lyrics[state.currentIndex].text
        : '';

    // 获取下一行歌词
    final nextIndex = state.currentIndex + 1;
    final nextLyrics = nextIndex >= 0 && nextIndex < state.lyrics.length
        ? state.lyrics[nextIndex].text
        : '';

    // 读取兼容模式设置
    final compatMode = prefs.getBluetoothCompatMode();

    _btLyrics.updateLyrics(
      lyrics: lyrics,
      nextLyrics: nextLyrics,
      title: song.title,
      artist: song.artist ?? '',
      compatMode: compatMode,
    );
  }
}
