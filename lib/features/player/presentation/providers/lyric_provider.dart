import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/bluetooth_detection_service.dart';
import '../../../../core/platform/bluetooth_lyrics_service.dart';
import '../../../../core/platform/live_activity_service.dart';
import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/lyric_parser.dart';
import 'player_provider.dart';

/// 歌词状态
class LyricState {
  final List<LyricLine> lyrics;
  final int currentIndex;
  final bool isLoading;
  final bool loadFailed;
  final String? rawLyricText;

  const LyricState({
    this.lyrics = const [],
    this.currentIndex = -1,
    this.isLoading = false,
    this.loadFailed = false,
    this.rawLyricText,
  });

  String get currentLyricText {
    if (currentIndex < 0 || currentIndex >= lyrics.length) return '';
    return lyrics[currentIndex].text;
  }

  String get nextLyricText {
    final next = currentIndex + 1;
    if (next < 0 || next >= lyrics.length) return '';
    return lyrics[next].text;
  }

  bool get hasLyrics => lyrics.isNotEmpty;

  LyricState copyWith({
    List<LyricLine>? lyrics,
    int? currentIndex,
    bool? isLoading,
    bool? loadFailed,
    String? rawLyricText,
    bool clearRawLyricText = false,
  }) {
    return LyricState(
      lyrics: lyrics ?? this.lyrics,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      loadFailed: loadFailed ?? this.loadFailed,
      rawLyricText:
          clearRawLyricText ? null : (rawLyricText ?? this.rawLyricText),
    );
  }
}

/// 歌词状态 Provider
///
/// 监听当前歌曲变化自动加载歌词，监听播放进度自动追踪当前行。
/// 仅在歌词行变化时通知下游，避免高频更新。
final lyricStateProvider = NotifierProvider<LyricNotifier, LyricState>(
  LyricNotifier.new,
);

class LyricNotifier extends Notifier<LyricState> {
  String? _lastLoadedUrl;
  final BluetoothLyricsService _btLyrics = BluetoothLyricsService();

  @override
  LyricState build() {
    final lyricUrl = ref.watch(
      playerStateProvider.select((s) => s.currentSong?.lyricUrl),
    );

    ref.listen(playerStateProvider.select((s) => s.currentTime), (prev, next) {
      _updateCurrentLine(next);
    });

    if (lyricUrl != null && lyricUrl.isNotEmpty) {
      Future.microtask(() => _loadLyrics(lyricUrl));
      return const LyricState(isLoading: true);
    }

    _lastLoadedUrl = null;
    return const LyricState();
  }

  void _updateCurrentLine(Duration position) {
    if (state.lyrics.isEmpty) return;
    final newIndex = LyricParser.findCurrentLine(state.lyrics, position);
    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);
      LiveActivityService().updateLyric(
        state.currentLyricText,
        state.nextLyricText,
      );
      // 方案 A：歌词页内推送蓝牙歌词
      _pushBluetoothLyrics();
    }
  }

  /// 方案 A：在歌词界面内推送蓝牙歌词（模式为 lyrics_screen_only 时激活）
  void _pushBluetoothLyrics() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final mode = prefs.getBluetoothLyricsMode();
      if (mode != BluetoothLyricsMode.lyricsScreenOnly) return;

      final btDetection = BluetoothDetectionService();
      final shouldPush = await btDetection.shouldPushLyrics(
        mode: mode,
        deviceNames: const [],
        isLyricsScreenOpen: true,
      );
      if (!shouldPush) return;

      final song = ref.read(playerStateProvider).currentSong;
      if (song == null) return;

      final lyrics = state.currentIndex >= 0 && state.currentIndex < state.lyrics.length
          ? state.lyrics[state.currentIndex].text
          : '';

      final nextIndex = state.currentIndex + 1;
      final nextLyrics = nextIndex >= 0 && nextIndex < state.lyrics.length
          ? state.lyrics[nextIndex].text
          : '';

      final compatMode = prefs.getBluetoothCompatMode();

      _btLyrics.updateLyrics(
        lyrics: lyrics,
        nextLyrics: nextLyrics,
        title: song.title,
        artist: song.artist ?? '',
        compatMode: compatMode,
      );
    } catch (e) {
      debugPrint('[LyricProvider] 蓝牙歌词推送失败: $e');
    }
  }

  Future<void> _loadLyrics(String? lyricUrl) async {
    if (lyricUrl == null || lyricUrl.isEmpty) {
      _lastLoadedUrl = null;
      state = const LyricState();
      return;
    }

    if (_lastLoadedUrl == lyricUrl && state.hasLyrics) return;

    state = state.copyWith(
      isLoading: true,
      loadFailed: false,
      lyrics: [],
      currentIndex: -1,
    );

    final cached = await LyricCacheService().get(lyricUrl);
    if (cached != null) {
      _lastLoadedUrl = lyricUrl;
      final lyrics = LyricParser.parse(cached);
      final position = ref.read(playerStateProvider).currentTime;
      final index = LyricParser.findCurrentLine(lyrics, position);
      state = LyricState(
        lyrics: lyrics,
        currentIndex: index,
        rawLyricText: cached,
      );
      LiveActivityService().updateLyric(
        state.currentLyricText,
        state.nextLyricText,
      );
      return;
    }

    try {
      final fullUrl = UrlHelper.buildLyricUrl(lyricUrl);
      final response = await Dio().get<Map<String, dynamic>>(fullUrl);

      String lyricText = '';
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final main = body['lyric'];
        if (main is String) lyricText = main;
      }

      _lastLoadedUrl = lyricUrl;
      final lyrics = LyricParser.parse(lyricText);
      final position = ref.read(playerStateProvider).currentTime;
      final index = LyricParser.findCurrentLine(lyrics, position);
      state = LyricState(
        lyrics: lyrics,
        currentIndex: index,
        rawLyricText: lyricText,
      );
      LiveActivityService().updateLyric(
        state.currentLyricText,
        state.nextLyricText,
      );

      if (lyricText.isNotEmpty) {
        await LyricCacheService().put(lyricUrl, lyricText);
      }
    } catch (e) {
      debugPrint('[LyricProvider] Failed to load lyric: $e');
      state = state.copyWith(isLoading: false, loadFailed: true);
    }
  }

  /// 强制重新加载歌词（歌词调整后调用）
  void invalidate() {
    _lastLoadedUrl = null;
    final lyricUrl = ref.read(playerStateProvider).currentSong?.lyricUrl;
    _loadLyrics(lyricUrl);
  }
}

/// 便捷 Provider：当前歌词行文本
final currentLyricTextProvider = Provider<String>((ref) {
  return ref.watch(lyricStateProvider).currentLyricText;
});

/// 便捷 Provider：下一行歌词文本
final nextLyricTextProvider = Provider<String>((ref) {
  return ref.watch(lyricStateProvider).nextLyricText;
});
