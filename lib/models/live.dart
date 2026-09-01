import 'package:latlong2/latlong.dart';

/// 한 사람의 현재 위치. 2초마다 갱신되므로 members와 분리해서 저장한다.
/// (합쳐두면 위치가 바뀔 때마다 팀 명단 화면까지 다시 그려진다)
class LivePosition {
  const LivePosition({
    required this.uid,
    required this.point,
    required this.accuracy,
    required this.heading,
    required this.timestamp,
    required this.dead,
  });

  final String uid;
  final LatLng point;
  final double accuracy;

  /// 북쪽 기준 방위각. 나침반이 없으면 null.
  final double? heading;
  final int timestamp;
  final bool dead;

  factory LivePosition.fromMap(String uid, Map<Object?, Object?> map) {
    return LivePosition(
      uid: uid,
      point: LatLng(
        (map['lat'] as num?)?.toDouble() ?? 0,
        (map['lng'] as num?)?.toDouble() ?? 0,
      ),
      accuracy: (map['acc'] as num?)?.toDouble() ?? 0,
      heading: (map['hdg'] as num?)?.toDouble(),
      timestamp: (map['ts'] as num?)?.toInt() ?? 0,
      dead: (map['dead'] ?? false) as bool,
    );
  }

  /// 마지막 갱신 이후 흐른 시간. 음영지역에서 위치가 멈췄는지 판단한다.
  Duration ageFrom(DateTime now) =>
      now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
}

/// 지도에 찍는 표식의 종류.
enum MarkType {
  enemy('적', '#F44336'),
  sniper('저격', '#9C27B0'),
  danger('위험', '#FF9800'),
  rally('집결', '#00BCD4');

  const MarkType(this.label, this.colorHex);

  final String label;
  final String colorHex;

  static MarkType parse(String? id) =>
      MarkType.values.where((t) => t.name == id).firstOrNull ?? MarkType.enemy;
}

/// 적 위치 등 임시 표식. 오래된 정보는 오히려 해로우므로 시간이 지나면 사라진다.
class MapMark {
  const MapMark({
    required this.id,
    required this.point,
    required this.type,
    required this.byUid,
    required this.createdAt,
  });

  final String id;
  final LatLng point;
  final MarkType type;
  final String byUid;
  final int createdAt;

  factory MapMark.fromMap(String id, Map<Object?, Object?> map) {
    return MapMark(
      id: id,
      point: LatLng(
        (map['lat'] as num?)?.toDouble() ?? 0,
        (map['lng'] as num?)?.toDouble() ?? 0,
      ),
      type: MarkType.parse(map['type'] as String?),
      byUid: (map['byUid'] ?? '') as String,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  Duration ageFrom(DateTime now) =>
      now.difference(DateTime.fromMillisecondsSinceEpoch(createdAt));
}

/// 거점 소유 상태.
enum Owner {
  us('아군', '#4CAF50'),
  enemy('적군', '#F44336'),
  neutral('중립', '#9E9E9E');

  const Owner(this.label, this.colorHex);

  final String label;
  final String colorHex;

  static Owner parse(String? id) =>
      Owner.values.where((o) => o.name == id).firstOrNull ?? Owner.neutral;
}

/// 점령 대상 거점. 방장이 등록하고, 상태는 누구나 바꿀 수 있다.
/// (무전으로 듣고 HQ가 대신 갱신하는 상황이 실제로 자주 나온다)
class Objective {
  const Objective({
    required this.id,
    required this.name,
    required this.point,
    required this.owner,
    required this.byCallsign,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final LatLng point;
  final Owner owner;
  final String byCallsign;
  final int updatedAt;

  factory Objective.fromMap(String id, Map<Object?, Object?> map) {
    return Objective(
      id: id,
      name: (map['name'] ?? '?') as String,
      point: LatLng(
        (map['lat'] as num?)?.toDouble() ?? 0,
        (map['lng'] as num?)?.toDouble() ?? 0,
      ),
      owner: Owner.parse(map['owner'] as String?),
      byCallsign: (map['byCallsign'] ?? '') as String,
      updatedAt: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 알림과 사망 지점 핀의 원본. 두 기능이 같은 데이터를 쓴다.
enum EventType { death, revive, objective }

class GameEvent {
  const GameEvent({
    required this.id,
    required this.type,
    required this.callsign,
    required this.teamName,
    required this.detail,
    required this.point,
    required this.timestamp,
  });

  final String id;
  final EventType type;
  final String callsign;
  final String teamName;
  final String detail;
  final LatLng? point;
  final int timestamp;

  factory GameEvent.fromMap(String id, Map<Object?, Object?> map) {
    final lat = (map['lat'] as num?)?.toDouble();
    final lng = (map['lng'] as num?)?.toDouble();
    return GameEvent(
      id: id,
      type: EventType.values
              .where((t) => t.name == map['type'])
              .firstOrNull ??
          EventType.death,
      callsign: (map['callsign'] ?? '?') as String,
      teamName: (map['teamName'] ?? '') as String,
      detail: (map['detail'] ?? '') as String,
      point: (lat == null || lng == null) ? null : LatLng(lat, lng),
      timestamp: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }

  Duration ageFrom(DateTime now) =>
      now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp));

  String get message => switch (type) {
        EventType.death => '$teamName $callsign 다운',
        EventType.revive => '$teamName $callsign 복귀',
        EventType.objective => '$detail ($callsign)',
      };
}

/// 팀별 리스폰(베이스) 지점. 방장이 게임 전에 잡아둔다.
class Spawn {
  const Spawn({required this.teamId, required this.point});

  final String teamId;
  final LatLng point;

  factory Spawn.fromMap(String teamId, Map<Object?, Object?> map) => Spawn(
        teamId: teamId,
        point: LatLng(
          (map['lat'] as num?)?.toDouble() ?? 0,
          (map['lng'] as num?)?.toDouble() ?? 0,
        ),
      );
}

/// 대회 전에 공지된 거점·베이스 배치를 저장해 둔 것.
/// 방은 게임마다 새로 만들지만 필드 배치는 그대로 재사용한다.
/// 팀은 방마다 id가 달라지므로 이름을 기준으로 저장한다.
class FieldPreset {
  const FieldPreset({
    required this.id,
    required this.name,
    required this.objectives,
    required this.spawns,
    required this.boundary,
    required this.createdBy,
  });

  final String id;
  final String name;

  /// (거점 이름, 좌표)
  final List<({String name, LatLng point})> objectives;

  /// 팀 이름 -> 리스폰 좌표
  final Map<String, LatLng> spawns;

  /// 경기장 경계 다각형. 3점 미만이면 그리지 않는다.
  final List<LatLng> boundary;
  final String createdBy;

  factory FieldPreset.fromMap(String id, Map<Object?, Object?> map) {
    final rawObjectives = map['objectives'];
    final rawSpawns = map['spawns'];
    final rawBoundary = map['boundary'];

    return FieldPreset(
      id: id,
      name: (map['name'] ?? '이름 없음') as String,
      createdBy: (map['createdBy'] ?? '') as String,
      boundary: parsePointList(rawBoundary),
      objectives: rawObjectives is List
          ? rawObjectives
              .whereType<Map>()
              .map((o) => (
                    name: (o['name'] ?? '?') as String,
                    point: LatLng(
                      (o['lat'] as num?)?.toDouble() ?? 0,
                      (o['lng'] as num?)?.toDouble() ?? 0,
                    ),
                  ))
              .toList()
          : const [],
      spawns: rawSpawns is Map
          ? {
              for (final e in rawSpawns.entries)
                if (e.value is Map)
                  e.key as String: LatLng(
                    ((e.value as Map)['lat'] as num?)?.toDouble() ?? 0,
                    ((e.value as Map)['lng'] as num?)?.toDouble() ?? 0,
                  ),
            }
          : const {},
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'createdBy': createdBy,
        'objectives': [
          for (final o in objectives)
            {'name': o.name, 'lat': o.point.latitude, 'lng': o.point.longitude},
        ],
        'spawns': {
          for (final e in spawns.entries)
            e.key: {'lat': e.value.latitude, 'lng': e.value.longitude},
        },
        'boundary': [
          for (final p in boundary) {'lat': p.latitude, 'lng': p.longitude},
        ],
      };
}


/// 서버가 준 좌표 배열을 읽는다. 경계선처럼 순서가 중요한 값에 쓴다.
List<LatLng> parsePointList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((p) => LatLng(
            (p['lat'] as num?)?.toDouble() ?? 0,
            (p['lng'] as num?)?.toDouble() ?? 0,
          ))
      .toList();
}
