import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> clearBrowserCache() async {
  final caches = web.window.caches;
  final cacheNames = (await caches.keys().toDart).toDart;

  // 在删除 Cache Storage 之前，先收集所有已缓存资源的 URL。
  // 浏览器有两层独立的缓存：
  //   1. Cache Storage API — Service Worker 管理的缓存，JS 可直接删除
  //   2. HTTP 缓存 — 受 Cache-Control max-age 控制，JS 无法直接清除
  // 仅清 Cache Storage 不够，还需用 fetch(cache:'reload') 逐个刷新 HTTP 缓存。
  final cachedUrls = <String>{};
  for (final name in cacheNames) {
    try {
      final cache = await caches.open(name.toDart).toDart;
      final requests = (await cache.keys().toDart).toDart;
      for (final request in requests) {
        cachedUrls.add(request.url);
      }
    } catch (_) {}
    await caches.delete(name.toDart).toDart;
  }

  try {
    final container = web.window.navigator.serviceWorker;
    final registrations = (await container.getRegistrations().toDart).toDart;
    for (final reg in registrations) {
      await reg.unregister().toDart;
    }
  } catch (_) {
    // Service Worker API 可能不可用（如 HTTP 环境）
  }

  // index.html 和 Flutter 引导文件可能只在 HTTP 缓存中而不在 Cache Storage，
  // 必须一并 force-refresh，否则 reload 仍会加载旧版本。
  final base = web.window.location.origin;
  final basePath = _getBasePath();
  for (final path in [
    basePath,
    '${basePath}index.html',
    '${basePath}flutter_bootstrap.js',
    '${basePath}flutter_service_worker.js',
    '${basePath}main.dart.js',
  ]) {
    cachedUrls.add('$base$path');
  }

  final init = web.RequestInit(cache: 'reload');
  for (final url in cachedUrls) {
    try {
      await web.window.fetch(url.toJS, init).toDart;
    } catch (_) {}
  }
}

String _getBasePath() {
  final path = web.window.location.pathname;
  // 对于子路径部署（如 /songloft/），保留完整前缀；根路径返回 '/'
  if (path.endsWith('/')) return path;
  final lastSlash = path.lastIndexOf('/');
  return lastSlash >= 0 ? path.substring(0, lastSlash + 1) : '/';
}

void reloadPage() {
  web.window.location.reload();
}
