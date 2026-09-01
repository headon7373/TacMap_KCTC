import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

/// 지도 타일을 기기에 저장해 두고 먼저 꺼내 쓴다.
///
/// KCTC 일대는 산악 지형이라 통신이 끊기는 구간이 있다. 그때 타일을 못 받으면
/// 지도가 회색으로 비어버리는데, 그러면 상황판으로서 쓸모가 없다.
/// 대회 전에 필드 영역을 미리 받아두면 통신이 끊겨도 지도는 그대로 보인다.
class TileCache {
  TileCache._();

  static final TileCache instance = TileCache._();

  Directory? _root;

  Future<Directory> _dir(String sourceId) async {
    _root ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${_root!.path}/tiles/$sourceId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> fileFor(String sourceId, int z, int x, int y) async =>
      File('${(await _dir(sourceId)).path}/${z}_${x}_$y.png');

  /// 저장된 타일이 있으면 그걸 쓰고, 없으면 받아서 저장한다.
  Future<Uint8List?> load(String sourceId, String url, int z, int x, int y,
      {bool networkAllowed = true}) async {
    final file = await fileFor(sourceId, z, x, y);
    if (await file.exists()) return file.readAsBytes();
    if (!networkAllowed) return null;

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'TacMapKCTC/1.0'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(response.bodyBytes);
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// 지정한 영역을 확대 단계별로 미리 받아둔다.
  Future<void> downloadArea({
    required String sourceId,
    required String urlTemplate,
    required LatLng center,
    required double radiusMeters,
    required int minZoom,
    required int maxZoom,
    required void Function(int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final tiles = <({int z, int x, int y})>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final range = _tileRange(center, radiusMeters, z);
      for (var x = range.minX; x <= range.maxX; x++) {
        for (var y = range.minY; y <= range.maxY; y++) {
          tiles.add((z: z, x: x, y: y));
        }
      }
    }

    var done = 0;
    onProgress(0, tiles.length);
    for (final t in tiles) {
      if (isCancelled()) return;
      final url = urlTemplate
          .replaceAll('{z}', '${t.z}')
          .replaceAll('{x}', '${t.x}')
          .replaceAll('{y}', '${t.y}');
      await load(sourceId, url, t.z, t.x, t.y);
      done++;
      if (done % 5 == 0 || done == tiles.length) onProgress(done, tiles.length);
    }
  }

  /// 미리 받기 전에 몇 장인지 알려준다. 수천 장이면 시간이 오래 걸린다.
  int estimateTileCount({
    required LatLng center,
    required double radiusMeters,
    required int minZoom,
    required int maxZoom,
  }) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final r = _tileRange(center, radiusMeters, z);
      total += (r.maxX - r.minX + 1) * (r.maxY - r.minY + 1);
    }
    return total;
  }

  Future<int> cachedBytes(String sourceId) async {
    final dir = await _dir(sourceId);
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear(String sourceId) async {
    final dir = await _dir(sourceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

({int minX, int maxX, int minY, int maxY}) _tileRange(
  LatLng center,
  double radiusMeters,
  int zoom,
) {
  // 위도 1도는 약 111km. 경도는 위도가 올라갈수록 짧아진다.
  final latDelta = radiusMeters / 111320;
  final lngDelta =
      radiusMeters / (111320 * math.cos(center.latitude * math.pi / 180));

  final a = _toTile(center.latitude + latDelta, center.longitude - lngDelta, zoom);
  final b = _toTile(center.latitude - latDelta, center.longitude + lngDelta, zoom);

  return (
    minX: math.min(a.x, b.x),
    maxX: math.max(a.x, b.x),
    minY: math.min(a.y, b.y),
    maxY: math.max(a.y, b.y),
  );
}

({int x, int y}) _toTile(double lat, double lng, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final x = ((lng + 180) / 360 * n).floor();
  final latRad = lat * math.pi / 180;
  final y = ((1 -
              math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
          2 *
          n)
      .floor();
  return (x: x.clamp(0, n.toInt() - 1), y: y.clamp(0, n.toInt() - 1));
}

/// flutter_map이 타일을 요청할 때 캐시를 먼저 뒤지게 하는 provider.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({required this.sourceId});

  final String sourceId;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      sourceId: sourceId,
      url: getTileUrl(coordinates, options),
      coordinates: coordinates,
    );
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({
    required this.sourceId,
    required this.url,
    required this.coordinates,
  });

  final String sourceId;
  final String url;
  final TileCoordinates coordinates;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await TileCache.instance.load(
      sourceId,
      url,
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );
    if (bytes == null) throw StateError('타일을 받지 못했습니다: $url');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage &&
      other.sourceId == sourceId &&
      other.url == url;

  @override
  int get hashCode => Object.hash(sourceId, url);
}
