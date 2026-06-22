import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/bluetooth_detection_service.dart';
import '../../../../core/platform/bluetooth_lyrics_service.dart';
import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/lyric_parser.dart';
import 'player_provider.dart';

/// 蓝牙歌词状态
class BluetoothLyricsState {
  final bool isBluetoothConnected;
  final List<LyricLine> lyrics;
  final int currentIndex;
  final String mode;

  const BluetoothLyricsState({
    this.isBluetoothConnected = false,
    this.lyrics = const [],
    this.currentIndex = -1,
    this.mode = BluetoothLyricsMode.off,
  });

  BluetoothLyricsState copyWith({
    bool? isBluetoothConnected,
    List<LyricLine>? lyrics,
    int? currentIndex,
    String? mode,
  }) {
    return BluetoothLyricsState(
      isBluetoothConnected: isBluetoothConnected ?? this.isBluetoothConnected,
      lyrics: lyrics ?? this.lyrics,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
    );
  }
}

/// 独立的蓝牙歌词 Provider
///
/// 处理 always / specific_device / force 模式（后台推送，不依赖歌词 UI）。
/// lyrics_screen_only 模式由 lyricStateProvider 处理。
final bluetoothLyricsProvider =
    NotifierProvider<BluetoothLyricsNotifier, BluetoothLyricsState>(
  BluetoothLyricsNotifier.new,
);

class BluetoothLyricsNotifier extends Notifier<BluetoothLyricsState> {
  String? _lastLoadedLyricUrl;
  final BluetoothLyricsService _btLyrics = BluetoothLyricsService();
  final BluetoothDetectionService _btDetection = BluetoothDetectionService();

  @override
  BluetoothLyricsState build() {
    // 直接读取当前蓝牙状态（避免 StreamProvider 丢失初始值）
    final initialConnected = _btDetection.isBluetoothConnected;

    // 订阅蓝牙状态变化流
    final sub = _btDetection.isBluetoothConnectedStream.listen((connected) {
      debugPrint('[BluetoothLyrics] 蓝牙状态变化: $connected');
      state = state.copyWith(isBluetoothConnected: connected);
      if (!connected) {
        _btLyrics.restoreMetadata();
      }
    });
    ref.onDispose(sub.cancel);

    // 监听当前歌曲变化
    ref.listen(playerStateProvider.select((s) => s.currentSong), (prev, next) {
      debugPrint('[BluetoothLyrics] 歌曲变化: ${next?.title}');
      // 通知原生端更新缓存的元数据（同时重置内部状态）
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

    // 加载初始模式
    _loadMode();

    return BluetoothLyricsState(
      isBluetoothConnected: initialConnected,
      mode: BluetoothLyricsMode.off,
    );
  }

  /// 从 SharedPreferences 加载当前模式
  void _loadMode() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final mode = prefs.getBluetoothLyricsMode();
      state = state.copyWith(mode: mode);
    } catch (e) {
      debugPrint('[BluetoothLyrics] 加载模式失败: $e');
    }
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
  void _updateCurrentLine(Duration position) async {
    if (state.lyrics.isEmpty) return;

    final newIndex = LyricParser.findCurrentLine(state.lyrics, position);
    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);

      // 从 SharedPreferences 实时读取模式（不依赖缓存的 state.mode）
      final prefs = await ref.read(appPreferencesProvider.future);
      final mode = prefs.getBluetoothLyricsMode();
      final deviceNames = prefs.getBluetoothDeviceNames();

      final shouldPush = await _btDetection.shouldPushLyrics(
        mode: mode,
        deviceNames: deviceNames,
      );
      if (!shouldPush) return;

      _sendLyricsToBluetooth();
    }
  }

  /// 发送歌词到蓝牙
  void _sendLyricsToBluetooth() {
    final song = ref.read(playerStateProvider).currentSong;
    if (song == null) return;

    final lyrics = state.currentIndex >= 0 && state.currentIndex < state.lyrics.length
        ? state.lyrics[state.currentIndex].text
        : '';

    _btLyrics.updateLyrics(
      lyrics: lyrics,
      title: song.title,
      artist: song.artist ?? '',
    );
  }
}
