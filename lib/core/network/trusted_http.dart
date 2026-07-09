import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 内置 CA 证书的懒加载缓存
Uint8List? _cachedCertBytes;

Future<Uint8List> _loadCertBytes() async {
  if (_cachedCertBytes != null) return _cachedCertBytes!;
  final data = await rootBundle.load('assets/certs/ca.crt');
  _cachedCertBytes = data.buffer.asUint8List();
  return _cachedCertBytes!;
}

/// 为 Dio 实例注入内置 CA 证书信任链（非 Web 平台）。
/// Dart 的 HttpClient 不会自动读取 Android 系统信任凭据，
/// 必须手动加载 CA 证书到 SecurityContext。
Future<void> applyTrustedCertificate(Dio dio) async {
  if (kIsWeb) return;

  final certBytes = await _loadCertBytes();
  final context = SecurityContext()..setTrustedCertificatesBytes(certBytes);

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: context),
  );
}

/// 创建带 CA 信任链的 HttpClient（用于不需要 Dio 的场景）。
Future<HttpClient?> createTrustedHttpClient() async {
  if (kIsWeb) return null;
  final certBytes = await _loadCertBytes();
  final context = SecurityContext()..setTrustedCertificatesBytes(certBytes);
  return HttpClient(context: context);
}
