import 'live.dart';
import 'room.dart';

/// 게임이 끝나고 돌아볼 숫자들. 기록(events)에서 뽑아낸다.
class GameStats {
  const GameStats({
    required this.totalDeaths,
    required this.deathsBySquad,
    required this.deathsByPlayer,
    required this.objectiveChanges,
    required this.changesByPlayer,
    required this.duration,
  });

  final int totalDeaths;

  /// 분대 이름 -> 사망 횟수
  final Map<String, int> deathsBySquad;

  /// 이름 -> 사망 횟수
  final Map<String, int> deathsByPlayer;

  final int objectiveChanges;

  /// 이름 -> 거점 상태를 바꾼 횟수
  final Map<String, int> changesByPlayer;

  /// 첫 기록부터 마지막 기록까지 걸린 시간
  final Duration duration;

  bool get isEmpty => totalDeaths == 0 && objectiveChanges == 0;
}

GameStats buildStats({
  required List<GameEvent> events,
  required List<Team> teams,
}) {
  final deathsBySquad = <String, int>{for (final t in teams) t.name: 0};
  final deathsByPlayer = <String, int>{};
  final changesByPlayer = <String, int>{};
  var totalDeaths = 0;
  var objectiveChanges = 0;

  for (final e in events) {
    switch (e.type) {
      case EventType.death:
        totalDeaths++;
        final squad = e.teamName.isEmpty ? '미배정' : e.teamName;
        deathsBySquad[squad] = (deathsBySquad[squad] ?? 0) + 1;
        deathsByPlayer[e.callsign] = (deathsByPlayer[e.callsign] ?? 0) + 1;
      case EventType.objective:
        objectiveChanges++;
        changesByPlayer[e.callsign] = (changesByPlayer[e.callsign] ?? 0) + 1;
      case EventType.revive:
        break;
    }
  }

  final times = events.map((e) => e.timestamp).where((t) => t > 0).toList()
    ..sort();
  final duration = times.length < 2
      ? Duration.zero
      : Duration(milliseconds: times.last - times.first);

  return GameStats(
    totalDeaths: totalDeaths,
    deathsBySquad: deathsBySquad,
    deathsByPlayer: deathsByPlayer,
    objectiveChanges: objectiveChanges,
    changesByPlayer: changesByPlayer,
    duration: duration,
  );
}

/// 값이 큰 순서로 정렬한 목록. 화면에 그대로 뿌린다.
List<MapEntry<String, int>> ranked(Map<String, int> counts) {
  final list = counts.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return list;
}
