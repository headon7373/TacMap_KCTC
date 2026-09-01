import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tacmap/models/room.dart';
import 'package:tacmap/models/tile_source.dart';
import 'package:tacmap/screens/map_screen.dart';

void main() {
  group('Member.fromMap', () {
    test('서버가 준 값을 그대로 읽는다', () {
      final m = Member.fromMap('uid-1', {
        'callsign': '독수리',
        'teamId': 'left',
        'isHost': true,
        'joinedAt': 1700000000000,
      });

      expect(m.uid, 'uid-1');
      expect(m.callsign, '독수리');
      expect(m.teamId, 'left');
      expect(m.isHost, isTrue);
    });

    test('팀 배정 전이면 teamId가 없다', () {
      final m = Member.fromMap('uid-2', {
        'callsign': '까치',
        'joinedAt': 1,
      });

      expect(m.teamId, isNull);
      expect(m.isHost, isFalse);
    });
  });

  group('Team.fromMap', () {
    test('16진수 색을 Color로 바꾼다', () {
      final t = Team.fromMap('left', {
        'name': '좌익',
        'color': '#2196F3',
        'order': 1,
      });

      expect(t.name, '좌익');
      expect(t.order, 1);
      expect(t.color, const Color(0xFF2196F3));
    });
  });

  test('기본 팀은 HQ/좌익/중앙/우익 네 개다', () {
    expect(defaultTeams.map((t) => t.name).toList(),
        ['HQ', '좌익', '중앙', '우익']);
  });

  group('parseLatLng', () {
    test('쉼표로 구분된 좌표를 읽는다', () {
      expect(parseLatLng('37.92, 128.33'), const LatLng(37.92, 128.33));
    });

    test('공백으로 구분해도 읽는다', () {
      expect(parseLatLng('37.92  128.33'), const LatLng(37.92, 128.33));
    });

    test('한국 밖 좌표는 오타로 보고 거부한다', () {
      expect(parseLatLng('137.92, 128.33'), isNull);
    });

    test('숫자가 아니면 거부한다', () {
      expect(parseLatLng('좌표아님'), isNull);
    });
  });

  group('compassLabel', () {
    test('8방위를 한글로 바꾼다', () {
      expect(compassLabel(0), '북');
      expect(compassLabel(90), '동');
      expect(compassLabel(180), '남');
      expect(compassLabel(270), '서');
      expect(compassLabel(45), '북동');
    });

    test('360도를 넘어가도 북으로 돌아온다', () {
      expect(compassLabel(361), '북');
      expect(compassLabel(359), '북');
    });
  });

  test('기본 배경 지도는 등고선이다', () {
    expect(defaultTileSource.id, 'topo');
  });

  group('Member 표기', () {
    test('등번호가 있으면 이름 앞에 붙인다', () {
      final m = Member.fromMap('uid', {
        'callsign': '김철수',
        'number': '7',
        'school': '건국대',
        'joinedAt': 1,
      });

      expect(m.displayName, '7 김철수');
      expect(m.school, '건국대');
    });

    test('등번호가 없으면 이름만 쓴다', () {
      final m = Member.fromMap('uid', {'callsign': '김철수', 'joinedAt': 1});

      expect(m.displayName, '김철수');
      expect(m.number, isEmpty);
      expect(m.school, isEmpty);
    });
  });
}
