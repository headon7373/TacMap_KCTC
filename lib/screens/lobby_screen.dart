import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/room.dart';
import '../services/room_service.dart';
import 'map_screen.dart';

/// 로비. 가로 화면을 좌우로 나눈다.
/// 왼쪽 = 분대 편성 현황(스크롤 없음), 오른쪽 = 전체 아군 명단 표(세로 스크롤).
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key, required this.service, required this.code});

  final RoomService service;
  final String code;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await service.leaveRoom(code);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: StreamBuilder<RoomMeta?>(
        stream: service.metaStream(code),
        builder: (context, metaSnap) {
          final isHost = metaSnap.data?.hostUid == service.uid;
          return StreamBuilder<List<Team>>(
            stream: service.teamsStream(code),
            builder: (context, teamSnap) {
              final teams = teamSnap.data ?? const <Team>[];
              return StreamBuilder<List<Member>>(
                stream: service.membersStream(code),
                builder: (context, memberSnap) {
                  final members = memberSnap.data ?? const <Member>[];
                  return Scaffold(
                    body: SafeArea(
                      child: Column(
                        children: [
                          _TopBar(
                            code: code,
                            total: members.length,
                            isHost: isHost,
                            onStart: () async {
                              if (isHost) {
                                await service.setRoomState(
                                  code: code,
                                  state: 'live',
                                );
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    MapScreen(service: service, code: code),
                              ));
                            },
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 240,
                                  child: _TeamPane(
                                    service: service,
                                    code: code,
                                    teams: teams,
                                    members: members,
                                    isHost: isHost,
                                  ),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(
                                  child: _RosterPane(
                                    service: service,
                                    code: code,
                                    teams: teams,
                                    members: members,
                                    isHost: isHost,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.code,
    required this.total,
    required this.isHost,
    required this.onStart,
  });

  final String code;
  final int total;
  final bool isHost;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Text('참가 코드', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 10),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
          IconButton(
            tooltip: '복사',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$code 복사됨')),
              );
            },
          ),
          const SizedBox(width: 16),
          Chip(
            avatar: const Icon(Icons.groups, size: 16),
            label: Text('$total명'),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.map),
            label: Text(isHost ? '게임 시작' : '지도로 이동'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(150, 44),
            ),
          ),
        ],
      ),
    );
  }
}

/// 왼쪽: 팀별 인원 현황. 팀 수가 적으니 남는 높이를 나눠 채워 스크롤이 필요 없다.
class _TeamPane extends StatelessWidget {
  const _TeamPane({
    required this.service,
    required this.code,
    required this.teams,
    required this.members,
    required this.isHost,
  });

  final RoomService service;
  final String code;
  final List<Team> teams;
  final List<Member> members;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final unassigned =
        members.where((m) => !teams.any((t) => t.id == m.teamId)).length;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Text('분대 편성', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final t in teams)
            Expanded(
              child: _TeamRow(
                name: t.name,
                color: t.color,
                count: members.where((m) => m.teamId == t.id).length,
              ),
            ),
          if (unassigned > 0)
            Expanded(
              child: _TeamRow(
                name: '미배정',
                color: Colors.blueGrey,
                count: unassigned,
              ),
            ),
          if (isHost) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addTeam(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('분대'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        teams.isEmpty ? null : () => _removeTeam(context),
                    icon: const Icon(Icons.remove, size: 16),
                    label: const Text('분대'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addTeam(BuildContext context) async {
    final name = await promptText(context, title: '분대 추가', hint: '분대 이름');
    if (name == null || name.isEmpty) return;
    await service.addTeam(
      code: code,
      name: name,
      color: '#9C27B0',
      order: teams.length,
    );
  }

  Future<void> _removeTeam(BuildContext context) async {
    final team = await showModalBottomSheet<Team>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('삭제할 분대 선택')),
              for (final t in teams)
                ListTile(
                  leading: CircleAvatar(backgroundColor: t.color, radius: 10),
                  title: Text(t.name),
                  onTap: () => Navigator.of(sheetContext).pop(t),
                ),
            ],
          ),
        ),
      ),
    );
    if (team == null) return;
    await service.removeTeam(code: code, teamId: team.id);
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.color,
    required this.count,
  });

  final String name;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Row(
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text(' 명', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// 오른쪽: 전체 아군 명단. 카드 격자라 15명이 스크롤 없이 들어간다.
class _RosterPane extends StatelessWidget {
  const _RosterPane({
    required this.service,
    required this.code,
    required this.teams,
    required this.members,
    required this.isHost,
  });

  final RoomService service;
  final String code;
  final List<Team> teams;
  final List<Member> members;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(child: Text('아직 아무도 들어오지 않았습니다'));
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                const Text(
                  '전체 아군',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${members.length}명',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          // 머리글은 고정하고 명단만 스크롤한다.
          const _RosterHeader(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: members.length,
              itemBuilder: (context, i) {
                final m = members[i];
                return _RosterRow(
                  member: m,
                  team: teams.where((t) => t.id == m.teamId).firstOrNull,
                  isMe: m.uid == service.uid,
                  height: 34,
                  onTap: () {
                    if (isHost || m.uid == service.uid) _manage(context, m);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _manage(BuildContext context, Member member) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  member.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(member.school.isEmpty ? '소속 미입력' : member.school),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('정보 수정'),
                subtitle: const Text('등번호 · 이름 · 소속대학'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _editInfo(context, member);
                },
              ),
              if (isHost) ...[
                ListTile(
                  leading: Icon(
                    member.spectator ? Icons.videocam_off : Icons.videocam,
                  ),
                  title: Text(member.spectator ? '경기 참가로 전환' : '관전으로 전환'),
                  subtitle: const Text('관전자는 위치를 보내지 않습니다'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await service.setSpectator(
                      code: code,
                      targetUid: member.uid,
                      spectator: !member.spectator,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('분대 배정'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _assign(context, member);
                  },
                ),
                if (member.uid != service.uid)
                  ListTile(
                    leading: const Icon(Icons.person_remove, color: Colors.red),
                    title: const Text(
                      '방에서 내보내기',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final ok = await confirmDialog(
                        context,
                        '${member.displayName} 을(를) 내보낼까요?',
                      );
                      if (!ok) return;
                      await service.kick(code: code, targetUid: member.uid);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editInfo(BuildContext context, Member member) async {
    final number = TextEditingController(text: member.number);
    final name = TextEditingController(text: member.callsign);
    final school = TextEditingController(text: member.school);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정보 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: number,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '등번호',
                  counterText: '',
                ),
              ),
              TextField(
                controller: name,
                maxLength: 12,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '이름',
                  counterText: '',
                ),
              ),
              TextField(
                controller: school,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: '소속대학',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    await service.setMemberInfo(
      code: code,
      targetUid: member.uid,
      callsign: name.text.trim(),
      number: number.text.trim(),
      school: school.text.trim(),
    );
  }

  Future<void> _assign(BuildContext context, Member member) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('분대 선택')),
              for (final t in teams)
                ListTile(
                  leading: CircleAvatar(backgroundColor: t.color, radius: 10),
                  title: Text(t.name),
                  onTap: () => Navigator.of(sheetContext).pop(t.id),
                ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueGrey,
                  radius: 10,
                ),
                title: const Text('미배정으로'),
                onTap: () => Navigator.of(sheetContext).pop(''),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await service.assignTeam(
      code: code,
      targetUid: member.uid,
      teamId: picked.isEmpty ? null : picked,
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Colors.white54,
    );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white24)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 34, child: Text('번호', style: style)),
          Expanded(flex: 3, child: Text('이름', style: style)),
          Expanded(flex: 2, child: Text('분대', style: style)),
          Expanded(flex: 3, child: Text('소속', style: style)),
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.member,
    required this.team,
    required this.isMe,
    required this.height,
    required this.onTap,
  });

  final Member member;
  final Team? team;
  final bool isMe;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = team?.color ?? Colors.blueGrey;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isMe ? color.withValues(alpha: 0.22) : null,
          border: const Border(
            bottom: BorderSide(color: Colors.white12),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: member.number.isEmpty
                  ? const Text('-', style: TextStyle(fontSize: 12))
                  : Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        member.number,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      member.callsign,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (member.isHost)
                    const Icon(Icons.star, size: 12, color: Colors.amber),
                  if (member.spectator)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.videocam, size: 12, color: Colors.cyan),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                team?.name ?? '미배정',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                member.school.isEmpty ? '-' : member.school,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 12,
        decoration: InputDecoration(hintText: hint, counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('확인'),
        ),
      ],
    ),
  );
  return result ?? false;
}
