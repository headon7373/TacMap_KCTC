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
class Member {
  const Member({
    required this.uid,
    required this.callsign,
    required this.teamId,
    required this.isHost,
    required this.joinedAt,
  });

  final String uid;
  final String callsign;

  /// 아직 팀 배정 전이면 null
  final String? teamId;
  final bool isHost;
  final int joinedAt;

  factory Member.fromMap(String uid, Map<Object?, Object?> map) {
    return Member(
      uid: uid,
      callsign: (map['callsign'] ?? '?') as String,
      teamId: map['teamId'] as String?,
      isHost: (map['isHost'] ?? false) as bool,
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
