/// 지도 배경으로 쓸 타일 서버 목록.
/// KCTC 같은 군사지역은 국내 포털이 가리기 때문에, 현장에서 어느 소스가
/// 제일 잘 보이는지 직접 비교해서 고를 수 있어야 한다. (QGroundControl과 같은 방식)
class TileSource {
  const TileSource({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    required this.maxZoom,
    this.note,
  });

  final String id;
  final String label;
  final String urlTemplate;
  final String attribution;
  final int maxZoom;
  final String? note;
}

const tileSources = <TileSource>[
  TileSource(
    id: 'esri',
    label: 'Esri 위성',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Esri, Maxar, Earthstar Geographics',
    maxZoom: 19,
  ),
  TileSource(
    id: 'google_sat',
    label: '구글 위성',
    urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    attribution: 'Google',
    maxZoom: 21,
    note: '비공식 타일. 내부용으로만 사용',
  ),
  TileSource(
    id: 'google_hybrid',
    label: '구글 위성+지명',
    urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    attribution: 'Google',
    maxZoom: 21,
    note: '비공식 타일. 내부용으로만 사용',
  ),
  TileSource(
    id: 'topo',
    label: '등고선',
    urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    attribution: 'OpenTopoMap (CC-BY-SA)',
    maxZoom: 17,
  ),
  TileSource(
    id: 'osm',
    label: '일반지도',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors',
    maxZoom: 19,
  ),
];

/// 기본 배경. 산악 지형에서는 등고선이 능선·계곡 판단에 가장 유용하다.
TileSource get defaultTileSource =>
    tileSources.firstWhere((s) => s.id == 'topo');
