import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/room.dart';
import '../services/room_service.dart';
import 'map_screen.dart';

/// 로비: 방 코드, 인원 명단, 방장 관리 기능.
/// 인원이 다 안 차도 언제든 지도로 넘어갈 수 있다.
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
          return Scaffold(
            appBar: AppBar(
              title: Text('로비  $code'),
              actions: [
                IconButton(
                  tooltip: '코드 복사',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$code 복사됨')),
                    );
                  },
                ),
              ],
            ),
            body: StreamBuilder<List<Team>>(
              stream: service.teamsStream(code),
              builder: (context, teamSnap) {
                final teams = teamSnap.data ?? const <Team>[];
                return Column(
                  children: [
                    if (isHost)
                      _HostToolbar(service: service, code: code, teams: teams),
                    Expanded(
                      child: _MemberList(
                        service: service,
                        code: code,
                        teams: teams,
                        isHost: isHost,
                      ),
                    ),
                  ],
                );
              },
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                  ),
                  icon: const Icon(Icons.map),
                  label: const Text('지도로 이동', style: TextStyle(fontSize: 18)),
                  onPressed: () async {
                    if (isHost) {
                      await service.setRoomState(code: code, state: 'live');
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MapScreen(service: service, code: code),
                    ));
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 방장 전용 줄: 팀 추가/삭제.
class _HostToolbar extends StatelessWidget {
  const _HostToolbar({
    required this.service,
    required this.code,
    required this.teams,
  });

  final RoomService service;
  final String code;
  final List<Team> teams;

  Future<void> _addTeam(BuildContext context) async {
    final name = await promptText(context, title: '팀 추가', hint: '팀 이름');
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('삭제할 팀 선택')),
            for (final t in teams)
              ListTile(
                leading: CircleAvatar(backgroundColor: t.color, radius: 10),
                title: Text(t.name),
                onTap: () => Navigator.of(sheetContext).pop(t),
              ),
          ],
        ),
      ),
    );
    if (team == null) return;
    await service.removeTeam(code: code, teamId: team.id);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Text('방장'),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _addTeam(context),
            icon: const Icon(Icons.group_add),
            label: const Text('팀 추가'),
          ),
          TextButton.icon(
            onPressed: teams.isEmpty ? null : () => _removeTeam(context),
            icon: const Icon(Icons.group_remove),
            label: const Text('팀 삭제'),
          ),
        ],
      ),
    );
  }
}

/// 팀별로 묶은 인원 명단. 항목을 누르면 관리 시트가 열린다.
class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.service,
    required this.code,
    required this.teams,
    required this.isHost,
  });

  final RoomService service;
  final String code;
  final List<Team> teams;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Member>>(
      stream: service.membersStream(code),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = snapshot.data!;
        final unassigned = <Member>[];
        final byTeam = <String, List<Member>>{
          for (final t in teams) t.id: <Member>[],
        };
        for (final m in members) {
          final list = m.teamId == null ? null : byTeam[m.teamId];
          if (list == null) {
            unassigned.add(m);
          } else {
            list.add(m);
          }
        }

        return ListView(
          children: [
            for (final t in teams)
              _TeamSection(
                team: t,
                members: byTeam[t.id]!,
                service: service,
                code: code,
                teams: teams,
                isHost: isHost,
              ),
            if (unassigned.isNotEmpty)
              _TeamSection(
                team: null,
                members: unassigned,
                service: service,
                code: code,
                teams: teams,
                isHost: isHost,
              ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '총 ${members.length}명',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.team,
    required this.members,
    required this.service,
    required this.code,
    required this.teams,
    required this.isHost,
  });

  final Team? team;
  final List<Member> members;
  final RoomService service;
  final String code;
  final List<Team> teams;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final color = team?.color ?? Colors.grey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: color.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: color, radius: 8),
              const SizedBox(width: 10),
              Text(
                team?.name ?? '미배정',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text('${members.length}명'),
            ],
          ),
        ),
        for (final m in members)
          ListTile(
            title: Text(m.callsign),
            trailing: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (m.isHost) const Chip(label: Text('방장')),
                if (m.uid == service.uid) const Chip(label: Text('나')),
                if (isHost || m.uid == service.uid) const Icon(Icons.more_vert),
              ],
            ),
            onTap: (isHost || m.uid == service.uid)
                ? () => _openManageSheet(context, m)
                : null,
          ),
      ],
    );
  }

  void _openManageSheet(BuildContext context, Member member) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                member.callsign,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(team?.name ?? '미배정'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('콜사인 변경'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final name = await promptText(
                  context,
                  title: '콜사인 변경',
                  hint: '새 콜사인',
                  initial: member.callsign,
                );
                if (name == null || name.isEmpty) return;
                await service.setCallsign(
                  code: code,
                  targetUid: member.uid,
                  callsign: name,
                );
              },
            ),
            if (isHost) ...[
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('팀 배정'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final picked = await _pickTeam(context);
                  if (picked == null) return;
                  await service.assignTeam(
                    code: code,
                    targetUid: member.uid,
                    teamId: picked.isEmpty ? null : picked,
                  );
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
                      '${member.callsign} 을(를) 내보낼까요?',
                    );
                    if (!ok) return;
                    await service.kick(code: code, targetUid: member.uid);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 빈 문자열을 고르면 미배정으로 되돌린다는 뜻.
  Future<String?> _pickTeam(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (pickContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('팀 선택')),
            for (final t in teams)
              ListTile(
                leading: CircleAvatar(backgroundColor: t.color, radius: 10),
                title: Text(t.name),
                onTap: () => Navigator.of(pickContext).pop(t.id),
              ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                radius: 10,
              ),
              title: const Text('미배정으로'),
              onTap: () => Navigator.of(pickContext).pop(''),
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
        decoration: InputDecoration(hintText: hint),
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
