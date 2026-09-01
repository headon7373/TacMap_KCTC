import 'package:flutter/material.dart';

import '../models/room.dart';

/// 한 팀의 생존 현황. "좌익 2/5"의 재료.
/// 미배정 인원도 같은 형태로 보여주기 때문에 team은 없을 수 있다.
class TeamStatus {
  const TeamStatus({
    required this.team,
    required this.name,
    required this.color,
    required this.alive,
    required this.total,
  });

  final Team? team;
  final String name;
  final Color color;
  final int alive;
  final int total;

  /// 절반 넘게 잃은 팀은 눈에 띄어야 한다. 여기가 뚫린 곳이다.
  bool get critical => total > 0 && alive * 2 <= total;

  bool get wipedOut => total > 0 && alive == 0;
}

/// 팀별 생존 수를 한 줄로. 전투 중에 흘끗 봐도 어디가 털렸는지 알 수 있게.
List<TeamStatus> buildTeamStatuses({
  required List<Team> teams,
  required List<Member> members,
  required Set<String> deadUids,
}) {
  final teamIds = teams.map((t) => t.id).toSet();

  final statuses = teams.map((team) {
    final roster = members.where((m) => m.teamId == team.id).toList();
    return TeamStatus(
      team: team,
      name: team.name,
      color: team.color,
      alive: roster.where((m) => !deadUids.contains(m.uid)).length,
      total: roster.length,
    );
  }).toList();

  // 팀에 안 넣은 사람도 화면에 보여야 한다. 안 보이면 편성 실수를 못 잡는다.
  final unassigned = members
      .where((m) => m.teamId == null || !teamIds.contains(m.teamId))
      .toList();
  if (unassigned.isNotEmpty) {
    statuses.add(TeamStatus(
      team: null,
      name: '미배정',
      color: Colors.blueGrey,
      alive: unassigned.where((m) => !deadUids.contains(m.uid)).length,
      total: unassigned.length,
    ));
  }

  return statuses;
}

class TeamStatusBar extends StatelessWidget {
  const TeamStatusBar({super.key, required this.statuses, this.onTap});

  final List<TeamStatus> statuses;
  final VoidCallback? onTap;

  int get _dead =>
      statuses.fold(0, (sum, s) => sum + (s.total - s.alive));

  int get _total => statuses.fold(0, (sum, s) => sum + s.total);

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: Colors.black.withValues(alpha: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final s in statuses) _TeamChip(status: s),
            _DeadCounter(dead: _dead, total: _total),
          ],
        ),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip({required this.status});

  final TeamStatus status;

  @override
  Widget build(BuildContext context) {
    final danger = status.critical;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          status.name,
          style: TextStyle(
            color: danger ? Colors.redAccent : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: status.wipedOut ? Colors.grey : status.color,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              '${status.alive}/${status.total}',
              style: TextStyle(
                color: danger ? Colors.redAccent : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


/// 전체 사망 인원. 팀별 숫자를 다 더하지 않아도 피해 규모가 바로 보인다.
class _DeadCounter extends StatelessWidget {
  const _DeadCounter({required this.dead, required this.total});

  final int dead;
  final int total;

  @override
  Widget build(BuildContext context) {
    final heavy = total > 0 && dead * 2 >= total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '사망',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off,
              size: 13,
              color: heavy ? Colors.redAccent : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              '$dead/$total',
              style: TextStyle(
                color: heavy ? Colors.redAccent : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
