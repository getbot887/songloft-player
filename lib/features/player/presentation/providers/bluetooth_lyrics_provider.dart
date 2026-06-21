import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/bluetooth_detection_service.dart';
import '../../../../core/platform/bluetooth_lyrics_service.dart';
import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../../main.dart';
import '../../domain/lyric_parser.dart';
import 'player_provider.dart';

/// 蓝牙歌词状态
class BluetoothLyricsState {
  final bool isBluetoothConnected;
  final List<LyricLine> lyrics;
  final int currentIndex;

  const BluetoothLyricsState({
    this.isBluetoothConnected = false,
    this.lyrics = const [],
    this.currentIndex = -1,
  });

  BluetoothLyricsState copyWith({
    bool? isBluetoothConnected,
    List<LyricLine>? lyrics,
    int? currentIndex,
  }) {
    return BluetoothLyricsState(
      isBluetoothConnected: isBluetoothConnected ?? this.isBluetoothConnected,
      lyrics: lyrics ?? this.lyrics,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

/// 独立的蓝牙歌词 Provider
///
/// 始终激活，不依赖歌词 UI。自动根据蓝牙连接状态启停歌词推送。
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
    // 初始化蓝牙歌词服务，传入 audio handler
    final audioHandler = ref.watch(audioHandlerProvider);
    _btLyrics.init(audioHandler);

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
      _btLyrics.onSongChanged();
      _loadLyrics(next?.lyricUrl);
    });

    // 监听播放进度变化
    ref.listen(playerStateProvider.select((s) => s.currentTime), (prev, next) {
      _updateCurrentLine(next);
    });

    return BluetoothLyricsState(isBluetoothConnected: initialConnected);
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
    if (!state.isBluetoothConnected) return;

    final newIndex = LyricParser.findCurrentLine(state.lyrics, position);
    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);
      _sendLyricsToBluetooth();
    }
  }

  /// 发送歌词到蓝牙
  void _sendLyricsToBluetooth() {
    if (!state.isBluetoothConnected) return;

    final song = ref.read(playerStateProvider).currentSong;
    if (song == null) return;

    final lyrics = state.currentIndex >= 0 && state.currentIndex < state.lyrics.length
        ? state.lyrics[state.currentIndex].text
        : '';

    _btLyrics.updateLyrics(
      lyrics: lyrics,
      title: song.title,
      artist: song.artist ?? '',
      compatMode: false, // 默认使用标准模式
    );
  }
}
