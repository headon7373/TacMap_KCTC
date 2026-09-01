import 'package:flutter/material.dart';

/// 방 하나의 기본 정보. 우리 편 전원이 이 방 하나에 들어온다.
class RoomMeta {
  const RoomMeta({
    required this.code,
    required this.hostUid,
    required this.state,
    required this.createdAt,
  });

  final String code;
  final String hostUid;

  /// lobby = 편성 중, live = 게임 중, ended = 종료
  final String state;
  final int createdAt;

  factory RoomMeta.fromMap(String code, Map<Object?, Object?> map) {
    return RoomMeta(
      code: code,
      hostUid: (map['hostUid'] ?? '') as String,
      state: (map['state'] ?? 'lobby') as String,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 편성 단위. 기본 4개(HQ/좌익/중앙/우익)로 시작하고 방장이 추가할 수 있다.
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.color,
    required this.order,
  });

  final String id;
  final String name;
  final Color color;
  final int order;

  factory Team.fromMap(String id, Map<Object?, Object?> map) {
    return Team(
      id: id,
      name: (map['name'] ?? '?') as String,
      color: _parseHex((map['color'] ?? '#9E9E9E') as String),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  static Color _parseHex(String hex) =>
      Color(int.parse(hex.replaceFirst('#', 'ff'), radix: 16));
}

/// 방에 들어온 사람. uid는 익명 로그인으로 발급된 고유 ID.
/// 대회 명단이 등번호·소속대학·이름으로 오기 때문에 그 세 가지를 그대로 담는다.
class Member {
  const Member({
    required this.uid,
    required this.callsign,
    required this.number,
    required this.school,
    required this.teamId,
    required this.isHost,
    required this.spectator,
    required this.joinedAt,
  });

  final String uid;

  /// 이름. 무전에서 부르는 호칭이기도 하다.
  final String callsign;

  /// 등번호. 없으면 빈 문자열.
  final String number;

  /// 소속 대학. 없으면 빈 문자열.
  final String school;

  /// 아직 팀 배정 전이면 null
  final String? teamId;
  final bool isHost;

  /// 관전자는 위치를 보내지 않고 화면만 본다. 생존 집계에서도 빠진다.
  /// 경기에 안 뛰는 인원이 무전을 듣고 거점 상태를 갱신해 주는 역할을 맡는다.
  final bool spectator;
  final int joinedAt;

  /// 명단에 쓰는 한 줄 표기. 등번호가 있으면 앞에 붙인다.
  String get displayName =>
      number.isEmpty ? callsign : '$number $callsign';

  factory Member.fromMap(String uid, Map<Object?, Object?> map) {
    return Member(
      uid: uid,
      callsign: (map['callsign'] ?? '?') as String,
      number: (map['number'] ?? '') as String,
      school: (map['school'] ?? '') as String,
      teamId: map['teamId'] as String?,
      isHost: (map['isHost'] ?? false) as bool,
      spectator: (map['spectator'] ?? false) as bool,
      joinedAt: (map['joinedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 방을 만들 때 자동 생성되는 기본 편성.
const defaultTeams = <({String id, String name, String color})>[
  (id: 'hq', name: 'HQ', color: '#FFC107'),
  (id: 'left', name: '좌익', color: '#2196F3'),
  (id: 'center', name: '중앙', color: '#4CAF50'),
  (id: 'right', name: '우익', color: '#FF5722'),
];
