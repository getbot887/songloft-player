import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'trusted_http.dart';

/// 带 CA 证书信任链的图片缓存管理器。
/// CachedNetworkImage 内部用 Dart HttpClient，需要手动注入 CA 证书。
class TrustedCacheManager extends CacheManager {
  static const key = 'songloftTrustedCache';

  static TrustedCacheManager? _instance;

  static Future<TrustedCacheManager> getInstance() async {
    if (_instance != null) return _instance!;
    final httpClient = await createTrustedHttpClient();
    final fileService = HttpFileService(httpClient: IOClient(httpClient));
    _instance = TrustedCacheManager._(fileService);
    return _instance!;
  }

  TrustedCacheManager._(FileService fileService)
      : super(Config(key, fileService: fileService));
}
