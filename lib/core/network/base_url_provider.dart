import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';

/// 当前生效的 API base URL。
///
/// 是 single source of truth：dioProvider ref.watch 它自动重建；
/// 同时 mirror 到 [AppConfig.baseUrl] 供少数非 Riverpod 上下文（如 url_helper、
/// jsplugin_grid 等字符串拼接）读取。运行期所有写入必须经此 Notifier。
class BaseUrlNotifier extends Notifier<String> {
  @override
  String build() => AppConfig.baseUrl;

  void set(String url) {
    if (state == url) return;
    state = url;
    AppConfig.baseUrl = url;
  }
}

final baseUrlProvider = NotifierProvider<BaseUrlNotifier, String>(
  BaseUrlNotifier.new,
);
