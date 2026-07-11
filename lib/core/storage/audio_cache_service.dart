import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../network/trusted_http.dart';

/// 音频缓存服务
///
/// 将下一首歌曲的音频预下载到临时目录，切歌时优先从本地文件播放，
/// 减少网络缓冲导致的蓝牙播放暂停。
class AudioCacheService {
  AudioCacheService._();
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;

  Directory? _cacheDir;

  /// 获取缓存目录（{tempDir}/audio_cache/）
  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null && await _cacheDir!.exists()) return _cacheDir!;
    final tempDir = await getTemporaryDirectory();
    _cacheDir = Directory('${tempDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// 构建缓存文件名：{songId}_{quality}.mp3
  String _cacheFileName(int songId, String? quality) {
    final q = (quality != null && quality.isNotEmpty && quality != 'original')
        ? quality
        : 'orig';
    return '${songId}_$q.mp3';
  }

  /// 检查歌曲是否已缓存，返回本地文件路径（null 表示未缓存）
  Future<String?> getCachePath(int songId, {String? quality}) async {
    if (kIsWeb) return null;
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheFileName(songId, quality)}');
      if (await file.exists()) return file.path;
    } catch (_) {}
    return null;
  }

  /// 下载歌曲音频到本地缓存
  ///
  /// [songUrl] 已拼接好 baseUrl + access_token 的完整播放 URL
  /// [songId] 歌曲 ID，用于文件命名
  /// [quality] 音质参数，用于文件命名
  /// 返回本地文件路径，失败返回 null
  Future<String?> cacheSong(
    String songUrl,
    int songId, {
    String? quality,
  }) async {
    if (kIsWeb || songUrl.isEmpty) return null;

    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheFileName(songId, quality)}');

      // 已缓存则跳过
      if (await file.exists()) return file.path;

      final dio = Dio();
      await applyTrustedCertificate(dio);

      final resp = await dio.get<List<int>>(
        songUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 400,
        ),
      );

      if (resp.data == null || resp.data!.isEmpty) return null;

      await file.writeAsBytes(resp.data!, flush: true);
      debugPrint(
        '[AudioCache] 缓存完成: ${file.path} '
        '(${resp.data!.length} bytes)',
      );
      return file.path;
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        debugPrint('[AudioCache] 缓存下载失败: $e');
      }
      return null;
    } catch (e) {
      debugPrint('[AudioCache] 缓存写入失败: $e');
      return null;
    }
  }

  /// 获取音频缓存目录大小（字节）
  Future<int> getCacheSize() async {
    if (kIsWeb) return 0;
    int total = 0;
    try {
      final dir = await _getCacheDir();
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }

  /// 清空音频缓存目录
  Future<void> clearCache() async {
    if (kIsWeb) return;
    try {
      final dir = await _getCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _cacheDir = null;
      }
    } catch (_) {}
  }
}
