import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tacmap/models/arena.dart';
import 'package:tacmap/models/live.dart';

void main() {
  group('FieldPreset', () {
    final preset = FieldPreset(
      id: 'p1',
      name: 'KCTC 도시지역',
      createdBy: 'uid-1',
      objectives: [
        (name: 'A', point: const LatLng(37.91, 128.18)),
        (name: 'B', point: const LatLng(37.92, 128.19)),
      ],
      spawns: {'좌익': const LatLng(37.90, 128.17)},
      boundary: [
        const LatLng(37.90, 128.17),
        const LatLng(37.93, 128.17),
        const LatLng(37.93, 128.20),
      ],
    );

    test('저장했다가 그대로 다시 읽는다', () {
      final restored = FieldPreset.fromMap('p1', preset.toMap());

      expect(restored.name, 'KCTC 도시지역');
      expect(restored.objectives.map((o) => o.name), ['A', 'B']);
      expect(restored.objectives.first.point.latitude, closeTo(37.91, 1e-9));
      expect(restored.spawns['좌익']!.longitude, closeTo(128.17, 1e-9));
      expect(restored.boundary.length, 3);
    });

    test('팀 이름으로 저장하므로 방이 달라져도 매칭된다', () {
      // 방마다 팀 id는 새로 생기지만 이름은 그대로 쓴다.
      final restored = FieldPreset.fromMap('p1', preset.toMap());
      expect(restored.spawns.keys, ['좌익']);
    });

    test('비어있는 필드도 안전하게 읽는다', () {
      final empty = FieldPreset.fromMap('x', {'name': '빈 프리셋'});

      expect(empty.objectives, isEmpty);
      expect(empty.spawns, isEmpty);
      expect(empty.boundary, isEmpty);
    });
  });

  group('parsePointList', () {
    test('좌표 순서를 유지한다', () {
      final points = parsePointList([
        {'lat': 1.0, 'lng': 2.0},
        {'lat': 3.0, 'lng': 4.0},
      ]);

      expect(points.first, const LatLng(1, 2));
      expect(points.last, const LatLng(3, 4));
    });

    test('리스트가 아니면 빈 값', () {
      expect(parsePointList(null), isEmpty);
      expect(parsePointList('경계'), isEmpty);
    });
  });

  group('arena', () {
    test('A 경기장은 KCTC 도시지역 훈련장 좌표를 갖는다', () {
      final a = arenaById('a');
      expect(a.name, 'A 경기장');
      expect(a.defaultCenter!.latitude, closeTo(37.9142876, 1e-7));
      expect(a.defaultCenter!.longitude, closeTo(128.1818486, 1e-7));
    });

    test('B 경기장은 좌표가 비어 있어 어드민이 입력한다', () {
      expect(arenaById('b').defaultCenter, isNull);
    });

    test('모르는 id는 첫 경기장으로 되돌린다', () {
      expect(arenaById('zzz').id, 'a');
      expect(arenaById(null).id, 'a');
    });
  });
}
