import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/live.dart';

/// 위치 전송 주기. 더 짧게 잡으면 배터리만 먹고 GPS 정확도가 못 따라온다.
const sendIntervalSeconds = 2;
const sendDistanceFilter = 3;

/// 게임 중 실시간 데이터(위치·표식·거점·이벤트)를 담당한다.
/// 방 편성은 RoomService, 전투 데이터는 이 클래스로 나눠 둔다.
class LiveService {
  LiveService({
    required this.code,
    FirebaseDatabase? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final String code;
  final FirebaseDatabase _db;
  final FirebaseAuth _auth;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;

  Position? _lastPosition;
  double? _heading;
  bool _dead = false;

  String get uid => _auth.currentUser!.uid;
  DatabaseReference get _room => _db.ref('rooms/$code');

  // ---- 위치 전송 ----

  /// 나침반 값은 지도 화면이 알려준다. 다음 전송에 함께 실린다.
  void updateHeading(double heading) => _heading = heading;

  /// 위치 전송을 시작한다.
  Future<void> startSharing() async {
    await stopSharing();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: sendDistanceFilter,
        intervalDuration: const Duration(seconds: sendIntervalSeconds),
        // 디스코드 같은 다른 앱을 앞에 띄워도 위치 전송이 끊기면 안 된다.
        // 안드로이드는 알림을 띄운 앱에만 백그라운드 위치를 계속 준다.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TacMap 위치 공유 중',
          notificationText: '분대에 내 위치를 보내는 중입니다',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen((position) {
      _lastPosition = position;
      _publish();
    });

    // 가만히 서 있어도 "살아있다"는 신호는 계속 보내야 한다.
    // 안 보내면 다른 사람 화면에서 내 마커가 오래된 것으로 흐려진다.
    _heartbeat = Timer.periodic(
      const Duration(seconds: sendIntervalSeconds * 3),
      (_) => _publish(),
    );
  }

  Future<void> stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> _publish() async {
    final p = _lastPosition;
    if (p == null) return;
    await _room.child('live/$uid').set({
      'lat': p.latitude,
      'lng': p.longitude,
      'acc': p.accuracy,
      if (_heading != null) 'hdg': _heading,
      'ts': ServerValue.timestamp,
      'dead': _dead,
    });
  }

  // ---- 사망 / 복귀 ----

  /// 사망 표시. 마지막 위치를 사망 지점으로 남겨서 적 화력 위치를 추정한다.
  Future<void> setDead({
    required bool dead,
    required String callsign,
    required String teamName,
  }) async {
    _dead = dead;
    await _room.child('live/$uid/dead').set(dead);

    final p = _lastPosition;
    await _room.child('events').push().set({
      'type': dead ? EventType.death.name : EventType.revive.name,
      'callsign': callsign,
      'teamName': teamName,
      if (p != null) 'lat': p.latitude,
      if (p != null) 'lng': p.longitude,
      'ts': ServerValue.timestamp,
    });
  }

  // ---- 적 표식 ----

  Future<void> addMark({
    required LatLng point,
    required MarkType type,
  }) =>
      _room.child('markers').push().set({
        'lat': point.latitude,
        'lng': point.longitude,
        'type': type.name,
        'byUid': uid,
        'createdAt': ServerValue.timestamp,
      });

  Future<void> removeMark(String id) => _room.child('markers/$id').remove();

  // ---- 거점 ----

  Future<void> addObjective({
    required String name,
    required LatLng point,
    required String callsign,
  }) =>
      _room.child('objectives').push().set({
        'name': name,
        'lat': point.latitude,
        'lng': point.longitude,
        'owner': Owner.neutral.name,
        'byCallsign': callsign,
        'ts': ServerValue.timestamp,
      });

  Future<void> setObjectiveOwner({
    required Objective objective,
    required Owner owner,
    required String callsign,
  }) async {
    await _room.child('objectives/${objective.id}').update({
      'owner': owner.name,
      'byCallsign': callsign,
      'ts': ServerValue.timestamp,
    });
    await _room.child('events').push().set({
      'type': EventType.objective.name,
      'callsign': callsign,
      'detail': '${objective.name} 거점 ${owner.label}',
      'lat': objective.point.latitude,
      'lng': objective.point.longitude,
      'ts': ServerValue.timestamp,
    });
  }

  Future<void> removeObjective(String id) =>
      _room.child('objectives/$id').remove();

  /// 운영자용 전체 기록. 누가 언제 무엇을 했는지 되짚을 때 쓴다.
  /// 점령 상태를 잘못 눌러도 누가 바꿨는지 남기 때문에 되돌릴 수 있다.
  Future<List<GameEvent>> fullLog({int limit = 500}) async {
    final snapshot =
        await _room.child('events').orderByChild('ts').limitToLast(limit).get();
    final value = snapshot.value;
    if (value is! Map) return const [];
    final list = value.entries
        .where((e) => e.value is Map)
        .map((e) => GameEvent.fromMap(
              e.key as String,
              (e.value as Map).cast<Object?, Object?>(),
            ))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  // ---- 리스폰 지점 (방장 전용) ----

  Future<void> setSpawn({required String teamId, required LatLng point}) =>
      _room.child('spawns/$teamId').set({
        'lat': point.latitude,
        'lng': point.longitude,
      });

  Future<void> clearSpawn(String teamId) =>
      _room.child('spawns/$teamId').remove();

  Stream<Map<String, Spawn>> spawnsStream() =>
      _room.child('spawns').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return <String, Spawn>{};
        return {
          for (final e in value.entries)
            if (e.value is Map)
              e.key as String: Spawn.fromMap(
                e.key as String,
                (e.value as Map).cast<Object?, Object?>(),
              ),
        };
      });

  // ---- 경기장 경계 (방장 전용) ----

  Future<void> setBoundary(List<LatLng> points) => _room.child('boundary').set([
        for (final p in points) {'lat': p.latitude, 'lng': p.longitude},
      ]);

  Future<void> clearBoundary() => _room.child('boundary').remove();

  Stream<List<LatLng>> boundaryStream() => _room
      .child('boundary')
      .onValue
      .map((event) => parsePointList(event.snapshot.value));

  // ---- 필드 프리셋 (방을 새로 만들어도 배치는 재사용) ----

  Future<void> savePreset(FieldPreset preset) =>
      _db.ref('presets').push().set(preset.toMap());

  Future<void> deletePreset(String id) => _db.ref('presets/$id').remove();

  Future<List<FieldPreset>> loadPresets() async {
    final snapshot = await _db.ref('presets').get();
    final value = snapshot.value;
    if (value is! Map) return const [];
    return value.entries
        .where((e) => e.value is Map)
        .map((e) => FieldPreset.fromMap(
              e.key as String,
              (e.value as Map).cast<Object?, Object?>(),
            ))
        .toList();
  }

  /// 프리셋을 현재 방에 적용한다. 기존 거점·리스폰은 지우고 새로 깐다.
  /// 팀은 이름으로 맞춘다 (방마다 팀 id가 달라지기 때문).
  Future<void> applyPreset({
    required FieldPreset preset,
    required Map<String, String> teamIdByName,
    required String callsign,
  }) async {
    await _room.child('objectives').remove();
    await _room.child('spawns').remove();
    await clearBoundary();
    if (preset.boundary.isNotEmpty) await setBoundary(preset.boundary);

    for (final o in preset.objectives) {
      await addObjective(name: o.name, point: o.point, callsign: callsign);
    }
    for (final entry in preset.spawns.entries) {
      final teamId = teamIdByName[entry.key];
      if (teamId == null) continue;
      await setSpawn(teamId: teamId, point: entry.value);
    }
  }

  // ---- 구독 ----

  Stream<Map<String, LivePosition>> positionsStream() =>
      _room.child('live').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return <String, LivePosition>{};
        return {
          for (final e in value.entries)
            if (e.value is Map)
              e.key as String: LivePosition.fromMap(
                e.key as String,
                (e.value as Map).cast<Object?, Object?>(),
              ),
        };
      });

  Stream<List<MapMark>> marksStream() =>
      _room.child('markers').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <MapMark>[];
        return value.entries
            .where((e) => e.value is Map)
            .map((e) => MapMark.fromMap(
                  e.key as String,
                  (e.value as Map).cast<Object?, Object?>(),
                ))
            .toList();
      });

  Stream<List<Objective>> objectivesStream() =>
      _room.child('objectives').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <Objective>[];
        final list = value.entries
            .where((e) => e.value is Map)
            .map((e) => Objective.fromMap(
                  e.key as String,
                  (e.value as Map).cast<Object?, Object?>(),
                ))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return list;
      });

  /// 최근 이벤트. 지도 화면은 적은 수만, 운영 로그는 많이 받아 본다.
  Stream<List<GameEvent>> eventsStream({int limit = 50}) => _room
      .child('events')
      .orderByChild('ts')
      .limitToLast(limit)
      .onValue
      .map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <GameEvent>[];
        final list = value.entries
            .where((e) => e.value is Map)
            .map((e) => GameEvent.fromMap(
                  e.key as String,
                  (e.value as Map).cast<Object?, Object?>(),
                ))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      });
}

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();

  @override
  String toString() => '위치 권한이 없어 팀에 내 위치를 보낼 수 없습니다.';
}
