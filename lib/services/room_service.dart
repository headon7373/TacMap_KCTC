import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/room.dart';

/// 방 생성/참가와 실시간 구독을 담당한다.
/// 화면(UI)은 이 클래스만 쓰고 Firebase를 직접 건드리지 않는다.
class RoomService {
  RoomService({FirebaseDatabase? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseDatabase _db;
  final FirebaseAuth _auth;
  final _random = Random.secure();

  String get uid => _auth.currentUser!.uid;

  DatabaseReference _room(String code) => _db.ref('rooms/$code');

  /// 6자리 숫자 코드. 장갑 낀 손으로도 빠르게 입력할 수 있게 숫자만 쓴다.
  String _newCode() =>
      List.generate(6, (_) => _random.nextInt(10)).join();

  /// 방을 만들고 기본 팀 4개를 함께 생성한다. 만든 사람이 방장이 된다.
  Future<String> createRoom({
    required String callsign,
    String number = '',
    String school = '',
  }) async {
    String code = _newCode();
    // 아주 낮은 확률이지만 코드가 겹치면 다시 뽑는다.
    for (var attempt = 0; attempt < 5; attempt++) {
      final existing = await _room(code).child('meta').get();
      if (!existing.exists) break;
      code = _newCode();
    }

    final now = ServerValue.timestamp;
    await _room(code).update({
      'meta': {
        'hostUid': uid,
        'state': 'lobby',
        'createdAt': now,
      },
      'teams': {
        for (var i = 0; i < defaultTeams.length; i++)
          defaultTeams[i].id: {
            'name': defaultTeams[i].name,
            'color': defaultTeams[i].color,
            'order': i,
          },
      },
      'members/$uid': {
        'callsign': callsign,
        'number': number,
        'school': school,
        'isHost': true,
        'joinedAt': now,
      },
    });
    return code;
  }

  /// 코드로 참가한다. 없는 방이면 예외를 던진다.
  Future<void> joinRoom({
    required String code,
    required String callsign,
    String number = '',
    String school = '',
    bool spectator = false,
  }) async {
    final meta = await _room(code).child('meta').get();
    if (!meta.exists) {
      throw RoomNotFoundException(code);
    }
    await _room(code).child('members/$uid').update({
      'callsign': callsign,
      'number': number,
      'school': school,
      'isHost': false,
      'spectator': spectator,
      'joinedAt': ServerValue.timestamp,
    });
  }

  Future<void> leaveRoom(String code) =>
      _room(code).child('members/$uid').remove();

  Stream<RoomMeta?> metaStream(String code) =>
      _room(code).child('meta').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return null;
        return RoomMeta.fromMap(code, value.cast<Object?, Object?>());
      });

  /// 참가 순서대로 정렬된 방 인원. 누가 들어오고 나가는지 실시간으로 반영된다.
  Stream<List<Member>> membersStream(String code) =>
      _room(code).child('members').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <Member>[];
        final members = value.entries
            .where((e) => e.value is Map)
            .map((e) => Member.fromMap(
                  e.key as String,
                  (e.value as Map).cast<Object?, Object?>(),
                ))
            .toList()
          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        return members;
      });

  Stream<List<Team>> teamsStream(String code) =>
      _room(code).child('teams').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <Team>[];
        final teams = value.entries
            .where((e) => e.value is Map)
            .map((e) => Team.fromMap(
                  e.key as String,
                  (e.value as Map).cast<Object?, Object?>(),
                ))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        return teams;
      });

  // ---- 방장 관리 기능 ----
  // 보안 규칙에서 teams 쓰기와 남의 members 쓰기는 방장(hostUid)만 허용된다.
  // 방장이 아닌 사람이 호출하면 서버가 거부한다.

  /// 명단 수정. 본인 것은 누구나, 남의 것은 방장만 바꿀 수 있다.
  Future<void> setMemberInfo({
    required String code,
    required String targetUid,
    required String callsign,
    required String number,
    required String school,
  }) =>
      _room(code).child('members/$targetUid').update({
        'callsign': callsign,
        'number': number,
        'school': school,
      });

  /// 팀 배정. teamId를 null로 주면 미배정으로 되돌린다.
  Future<void> assignTeam({
    required String code,
    required String targetUid,
    required String? teamId,
  }) =>
      _room(code).child('members/$targetUid/teamId').set(teamId);

  /// 방에서 내보낸다. 위치 기록도 함께 지운다.
  Future<void> kick({required String code, required String targetUid}) async {
    await _room(code).child('members/$targetUid').remove();
    await _room(code).child('live/$targetUid').remove();
  }

  Future<void> addTeam({
    required String code,
    required String name,
    required String color,
    required int order,
  }) =>
      _room(code).child('teams').push().set({
        'name': name,
        'color': color,
        'order': order,
      });

  /// 팀을 지우면 그 팀에 있던 사람은 미배정으로 돌린다.
  /// 남겨두면 존재하지 않는 팀을 가리키게 되어 화면이 깨진다.
  Future<void> removeTeam({
    required String code,
    required String teamId,
  }) async {
    final members = await _room(code).child('members').get();
    final value = members.value;
    if (value is Map) {
      for (final entry in value.entries) {
        final data = entry.value;
        if (data is Map && data['teamId'] == teamId) {
          await _room(code).child('members/${entry.key}/teamId').set(null);
        }
      }
    }
    await _room(code).child('teams/$teamId').remove();
  }

  /// 관전 여부 전환. 관전자는 위치를 보내지 않는다.
  Future<void> setSpectator({
    required String code,
    required String targetUid,
    required bool spectator,
  }) =>
      _room(code).child('members/$targetUid/spectator').set(spectator);

  /// 게임 상태 전환. 인원이 다 안 찼어도 방장이 언제든 시작할 수 있다.
  Future<void> setRoomState({required String code, required String state}) =>
      _room(code).child('meta/state').set(state);
}


class RoomNotFoundException implements Exception {
  const RoomNotFoundException(this.code);
  final String code;

  @override
  String toString() => '$code 번 방을 찾을 수 없습니다.';
}
