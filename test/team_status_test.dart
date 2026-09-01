import 'package:flutter_test/flutter_test.dart';
import 'package:tacmap/models/room.dart';
import 'package:tacmap/widgets/team_status_bar.dart';

Member member(String uid, String? teamId) => Member(
      uid: uid,
      callsign: uid,
      number: '',
      school: '',
      teamId: teamId,
      isHost: false,
      joinedAt: 0,
    );

Team team(String id, String name) => Team.fromMap(id, {
      'name': name,
      'color': '#2196F3',
      'order': 0,
    });

void main() {
  final left = team('left', '좌익');
  final center = team('center', '중앙');

  test('팀별 생존/전체 인원을 센다', () {
    final statuses = buildTeamStatuses(
      teams: [left, center],
      members: [
        member('a', 'left'),
        member('b', 'left'),
        member('c', 'center'),
      ],
      deadUids: {'b'},
    );

    expect(statuses[0].name, '좌익');
    expect(statuses[0].alive, 1);
    expect(statuses[0].total, 2);
    expect(statuses[1].alive, 1);
    expect(statuses[1].total, 1);
  });

  test('절반 이하로 줄면 위험으로 표시한다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: [member('a', 'left'), member('b', 'left')],
      deadUids: {'a'},
    );

    expect(statuses.single.critical, isTrue);
    expect(statuses.single.wipedOut, isFalse);
  });

  test('전멸을 따로 구분한다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: [member('a', 'left')],
      deadUids: {'a'},
    );

    expect(statuses.single.wipedOut, isTrue);
  });

  test('인원이 없는 팀은 위험으로 보지 않는다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: const [],
      deadUids: const {},
    );

    expect(statuses.single.critical, isFalse);
    expect(statuses.single.wipedOut, isFalse);
  });

  test('미배정 인원은 팀 집계에 섞이지 않는다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: [member('a', 'left'), member('z', null)],
      deadUids: const {},
    );

    expect(statuses.first.name, '좌익');
    expect(statuses.first.total, 1);
  });

  test('미배정 인원을 마지막 항목으로 따로 보여준다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: [member('a', 'left'), member('y', null), member('z', null)],
      deadUids: {'y'},
    );

    expect(statuses.length, 2);
    expect(statuses.last.name, '미배정');
    expect(statuses.last.alive, 1);
    expect(statuses.last.total, 2);
    expect(statuses.last.team, isNull);
  });

  test('없어진 팀에 남아있던 인원도 미배정으로 센다', () {
    final statuses = buildTeamStatuses(
      teams: [left],
      members: [member('a', 'deleted-team')],
      deadUids: const {},
    );

    expect(statuses.last.name, '미배정');
    expect(statuses.last.total, 1);
  });
}
