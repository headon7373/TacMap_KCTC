import 'package:latlong2/latlong.dart';

/// 대회장. 경기장이 여러 개라 매번 좌표를 치지 않고 골라 쓴다.
/// 좌표를 바꾸면 기기에 저장되어 다음에도 유지된다.
class Arena {
  const Arena({
    required this.id,
    required this.name,
    required this.defaultCenter,
  });

  final String id;
  final String name;

  /// 아직 좌표를 안 정한 경기장은 null. 앱에서 입력해 채운다.
  final LatLng? defaultCenter;

  /// 저장된 좌표를 찾을 때 쓰는 키.
  String get latKey => 'arena_${id}_lat';
  String get lngKey => 'arena_${id}_lng';
}

/// 경기장 좌표는 앱에 넣어두지 않는다. 대회마다 장소가 달라지기도 하고,
/// 특정 장소를 코드에 박아두면 앱의 쓰임이 그 장소에 묶인다.
/// 운영자가 첫 실행 때 기준점 버튼을 길게 눌러 좌표를 입력하면 기기에 저장된다.
const arenas = <Arena>[
  Arena(id: 'a', name: 'A 경기장', defaultCenter: null),
  Arena(id: 'b', name: 'B 경기장', defaultCenter: null),
];

Arena arenaById(String? id) =>
    arenas.where((a) => a.id == id).firstOrNull ?? arenas.first;
