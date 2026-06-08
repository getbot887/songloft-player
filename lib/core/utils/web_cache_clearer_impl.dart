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

  // 用 fetch cache:'reload' 强制从服务器重新拉取并更新 HTTP 缓存条目，
  // 这样后续 location.reload() 时浏览器使用的就是最新内容。
  if (cachedUrls.isNotEmpty) {
    final init = web.RequestInit(cache: 'reload');
    for (final url in cachedUrls) {
      try {
        await web.window.fetch(url.toJS, init).toDart;
      } catch (_) {}
    }
  }
}

void reloadPage() {
  web.window.location.reload();
}
