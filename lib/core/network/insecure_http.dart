import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// 创建接受自签证书的 HttpClientAdapter（非 Web 平台）。
/// Web 平台不需要此适配器，直接返回 null 即可。
IOHttpClientAdapter? createInsecureAdapter() {
  if (kIsWeb) return null;
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    },
  );
}

/// 为已有的 Dio 实例注入自签证书支持（非 Web 平台）。
void applyInsecureCertificate(Dio dio) {
  if (!kIsWeb) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );
  }
}
