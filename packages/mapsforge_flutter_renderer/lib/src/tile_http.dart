import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// Shared HTTP client for all online tile renderers (XYZ / WMTS / WMS). A single
/// instance keeps a connection pool and applies sane timeouts + a real
/// User-Agent (many tile servers 403 without one).
final Dio tileDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    responseType: ResponseType.bytes,
    followRedirects: true,
    headers: {'User-Agent': 'hikerbg/app (+https://hiker.bg)'},
    validateStatus: (status) => status != null && status >= 200 && status < 300,
  ),
);

/// Fetches [uri] and decodes it into a tile [JobResult]. Never throws — any
/// network error, non-2xx, empty body or decode failure returns
/// [JobResult.unsupported] so the tile queue substitutes a transparent tile
/// (overlay) or the "No data" placeholder (base). This keeps online-tile
/// failures off the global-zone FATAL path (the app is offline-first and these
/// requests routinely fail on airplane mode / throttling / server hiccups).
Future<JobResult> fetchTileImage(Uri uri) async {
  try {
    final response = await tileDio.getUri(uri);
    if (response.data == null) return JobResult.unsupported();
    final codec = await ui.instantiateImageCodec(response.data);
    final frame = await codec.getNextFrame();
    return JobResult.normal(TilePicture.fromBitmap(frame.image));
  } catch (_) {
    return JobResult.unsupported();
  }
}

/// Merges [params] into [baseUrl]'s query (preserving any query the endpoint
/// already carries, e.g. a `MAP=` param) and returns the full [Uri]. Used by the
/// KVP WMTS/WMS renderers.
Uri buildKvpUri(String baseUrl, Map<String, String> params) {
  final base = Uri.parse(baseUrl);
  final merged = <String, String>{...base.queryParameters, ...params};
  return base.replace(queryParameters: merged);
}
