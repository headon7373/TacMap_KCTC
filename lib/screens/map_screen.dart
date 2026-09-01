import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/arena.dart';
import '../models/live.dart';
import '../models/stats.dart';
import '../models/room.dart';
import '../models/tile_source.dart';
import '../services/live_service.dart';
import '../services/room_service.dart';
import '../services/tile_cache.dart';
import '../widgets/heading_marker.dart';
import '../widgets/hold_button.dart';
import '../widgets/objective_marker.dart';
import '../widgets/team_status_bar.dart';

/// 경기장 좌표를 아직 입력하지 않았을 때 지도가 열리는 위치.
/// 한반도 중앙 부근이며, 운영자가 기준점을 입력하면 거기로 옮겨간다.
const fallbackCenter = LatLng(36.5, 127.8);

/// 적 표식이 살아 있는 시간. 오래된 적 위치는 오히려 판단을 흐린다.
const markLifetime = Duration(seconds: 60);

/// 사망 지점 핀이 남는 시간. 적 화력 위치를 추정하는 용도.
const deathPinLifetime = Duration(minutes: 5);

/// 이 시간이 지나면 마커를 흐리게 해서 "오래된 위치"임을 알린다.
const staleAfter = Duration(seconds: 30);

enum MapOrientation { northUp, headingUp }

/// 게임 중 메인 화면. 가로 모드 기준으로 지도를 넓게 쓰고
/// 조작은 좌우 세로 패널에 몰아둔다. 위아래는 지도를 가리지 않는다.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.service, required this.code});

  final RoomService service;
  final String code;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  final _distance = const Distance();
  late final LiveService _live = LiveService(code: widget.code);

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _ticker;
  Timer? _toastTimer;

  List<Team> _teams = const [];
  List<Member> _members = const [];
  Map<String, LivePosition> _positions = const {};
  Map<String, Spawn> _spawns = const {};
  List<MapMark> _marks = const [];
  List<Objective> _objectives = const [];
  List<GameEvent> _events = const [];
  List<LatLng> _boundary = const [];
  String _hostUid = '';

  bool _eventsPrimed = false;
  final _seenEvents = <String>{};

  TileSource _source = defaultTileSource;
  Arena _arena = arenas.first;
  LatLng _basePoint = fallbackCenter;
  MapOrientation _orientation = MapOrientation.northUp;
  MarkType _markType = MarkType.enemy;

  double? _heading;
  double _mapRotation = 0;
  bool _mapReady = false;
  bool _sharing = false;
  String? _toast;
  double _holdProgress = 0;
  DateTime _now = DateTime.now();

  String get _uid => widget.service.uid;
  bool get _isHost => _hostUid == _uid;
  Member? get _me => _members.where((m) => m.uid == _uid).firstOrNull;
  bool get _amDead => _positions[_uid]?.dead ?? false;

  Team? _teamOf(Member? member) =>
      _teams.where((t) => t.id == member?.teamId).firstOrNull;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _restoreSettings();
    _listenCompass();
    _listenRoom();
    _startSharing();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _ticker?.cancel();
    _toastTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _live.stopSharing();
    super.dispose();
  }

  /// 화면 상단 중앙에 잠깐 떴다 사라지는 알림.
  /// 스낵바는 하단 버튼을 가려서 전투 중에 쓸 수 없다.
  void _showToast(String message) {
    setState(() => _toast = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _listenRoom() {
    _subs.addAll([
      widget.service.metaStream(widget.code).listen(
            (meta) => setState(() => _hostUid = meta?.hostUid ?? ''),
          ),
      widget.service
          .teamsStream(widget.code)
          .listen((v) => setState(() => _teams = v)),
      widget.service
          .membersStream(widget.code)
          .listen((v) => setState(() => _members = v)),
      _live.positionsStream().listen((v) => setState(() => _positions = v)),
      _live.spawnsStream().listen((v) => setState(() => _spawns = v)),
      _live.boundaryStream().listen((v) => setState(() => _boundary = v)),
      _live.marksStream().listen((v) => setState(() => _marks = v)),
      _live.objectivesStream().listen((v) => setState(() => _objectives = v)),
      _live.eventsStream().listen(_onEvents),
    ]);
  }

  /// 새 이벤트만 골라 진동으로 알린다.
  /// 화면을 안 보고 있어도 구분되도록 패턴을 다르게 준다.
  Future<void> _onEvents(List<GameEvent> events) async {
    final fresh = events.where((e) => !_seenEvents.contains(e.id)).toList();
    _seenEvents.addAll(events.map((e) => e.id));
    setState(() => _events = events);

    if (!_eventsPrimed) {
      _eventsPrimed = true;
      return;
    }
    if (fresh.isEmpty) return;

    if (fresh.any((e) => e.type == EventType.objective)) {
      await Vibration.vibrate(pattern: [0, 500, 200, 500]);
    } else if (fresh.any((e) => e.type == EventType.death)) {
      await Vibration.vibrate(duration: 200);
    }
    if (mounted) _showToast(fresh.first.message);
  }

  void _listenCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _subs.add(events.listen((event) {
      final heading = event.heading;
      if (heading == null || !mounted) return;
      _live.updateHeading(heading);
      setState(() => _heading = heading);
      if (_orientation == MapOrientation.headingUp && _mapReady) {
        _map.rotate(-heading);
      }
    }));
  }

  bool get _amSpectator => _me?.spectator ?? false;

  Future<void> _startSharing() async {
    if (_amSpectator) {
      if (mounted) _showToast('관전 모드 - 내 위치는 보내지 않습니다');
      return;
    }
    try {
      await _live.startSharing();
      if (mounted) setState(() => _sharing = true);
    } catch (e) {
      if (mounted) _showToast('$e');
    }
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedSource = prefs.getString('tileSource');
    final match = tileSources.where((s) => s.id == savedSource);
    final arena = arenaById(prefs.getString('arena'));
    setState(() {
      if (match.isNotEmpty) _source = match.first;
      _arena = arena;
      _basePoint = _centerOf(arena, prefs) ?? fallbackCenter;
    });
    _moveToBase();
  }

  /// 저장된 좌표가 있으면 그걸, 없으면 기본 좌표를 쓴다.
  LatLng? _centerOf(Arena arena, SharedPreferences prefs) {
    final lat = prefs.getDouble(arena.latKey);
    final lng = prefs.getDouble(arena.lngKey);
    if (lat != null && lng != null) return LatLng(lat, lng);
    return arena.defaultCenter;
  }

  void _moveToBase() {
    if (_mapReady) _map.move(_basePoint, 15);
  }

  Future<void> _pickArena() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final picked = await _sheet<Arena>(
      title: '경기장 선택',
      items: [
        for (final a in arenas)
          (
            icon: Icons.stadium,
            color: _centerOf(a, prefs) == null ? Colors.white38 : Colors.white,
            title: a.name,
            subtitle: _centerOf(a, prefs) == null
                ? '좌표 미설정 — 길게 눌러 입력'
                : '${_centerOf(a, prefs)!.latitude.toStringAsFixed(5)}, '
                    '${_centerOf(a, prefs)!.longitude.toStringAsFixed(5)}',
            selected: a.id == _arena.id,
            value: a,
          ),
      ],
    );
    if (picked == null) return;

    final center = _centerOf(picked, prefs);
    await prefs.setString('arena', picked.id);
    if (!mounted) return;
    setState(() => _arena = picked);

    if (center == null) {
      _showToast('${picked.name} 좌표가 없습니다. 기준점 버튼을 길게 눌러 입력하세요');
      return;
    }
    setState(() => _basePoint = center);
    _moveToBase();
  }

  Future<void> _selectSource(TileSource source) async {
    setState(() => _source = source);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tileSource', source.id);
  }

  void _toggleOrientation() {
    setState(() {
      _orientation = _orientation == MapOrientation.northUp
          ? MapOrientation.headingUp
          : MapOrientation.northUp;
    });
    if (!_mapReady) return;
    if (_orientation == MapOrientation.northUp) {
      _map.rotate(0);
    } else if (_heading != null) {
      _map.rotate(-_heading!);
    }
  }

  // ---- 액션 ----

  Future<void> _toggleDead() async {
    final me = _me;
    if (me == null) return;
    final next = !_amDead;
    await _live.setDead(
      dead: next,
      callsign: me.callsign,
      teamName: _teamOf(me)?.name ?? '미배정',
    );
    if (mounted) _showToast(next ? '사망 처리됨' : '복귀함');
  }

  /// 화면 중앙 십자선 위치에 표식을 찍는다.
  /// 뛰면서 지도를 정확히 탭하는 건 불가능에 가깝다.
  Future<void> _placeMark() async {
    if (!_mapReady) return;
    await _live.addMark(point: _map.camera.center, type: _markType);
    await Vibration.vibrate(duration: 40);
    _showToast('${_markType.label} 표시 (${markLifetime.inSeconds}초)');
  }

  Future<void> _pickMarkType() async {
    final picked = await _sheet<MarkType>(
      title: '표식 종류',
      items: [
        for (final t in MarkType.values)
          (
            icon: markIcon(t),
            color: hexColor(t.colorHex),
            title: t.label,
            subtitle: null,
            selected: t == _markType,
            value: t,
          ),
      ],
    );
    if (picked != null) setState(() => _markType = picked);
  }

  Future<void> _openSourceSheet() async {
    final picked = await _sheet<TileSource>(
      title: '지도 변경',
      items: [
        for (final s in tileSources)
          (
            icon: Icons.map,
            color: Colors.white70,
            title: s.label,
            subtitle: s.note ?? s.attribution,
            selected: s.id == _source.id,
            value: s,
          ),
      ],
    );
    if (picked != null) await _selectSource(picked);
  }

  Future<void> _changeOwner(Objective objective) async {
    final picked = await _sheet<Owner>(
      title: '${objective.name} 거점 상태',
      items: [
        for (final o in Owner.values)
          (
            icon: Icons.circle,
            color: hexColor(o.colorHex),
            title: o.label,
            subtitle: null,
            selected: o == objective.owner,
            value: o,
          ),
      ],
    );
    if (picked == null || picked == objective.owner) return;
    await _live.setObjectiveOwner(
      objective: objective,
      owner: picked,
      callsign: _me?.callsign ?? '?',
    );
  }

  // ---- 필드 설정 (방장) ----

  Future<void> _openFieldSetup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              const ListTile(
                leading: Icon(Icons.settings),
                title: Text('필드 설정'),
                subtitle: Text('화면 중앙 십자선 위치가 기준입니다'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_circle, color: Colors.green),
                title: const Text('거점 추가'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _addObjective();
                },
              ),
              for (final o in _objectives)
                ListTile(
                  dense: true,
                  leading: ObjectiveMarker(
                    name: o.name,
                    color: hexColor(o.owner.colorHex),
                    size: 28,
                  ),
                  title: Text(o.name),
                  subtitle: Text(o.owner.label),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _live.removeObjective(o.id),
                  ),
                ),
              const Divider(),
              ListTile(
                title: const Text('경기장 경계'),
                subtitle: Text(
                  _boundary.length < 3
                      ? '점 ${_boundary.length}개 · 3개 이상이면 영역이 그려집니다'
                      : '점 ${_boundary.length}개 · 영역 표시 중',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addBoundaryPoint,
                        icon: const Icon(Icons.add_location),
                        label: const Text('중앙에 점 추가'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _undoBoundaryPoint,
                      child: const Icon(Icons.undo),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await _live.clearBoundary();
                        _showToast('경계 지움');
                      },
                      child: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const ListTile(title: Text('분대 리스폰 지점')),
              for (final t in _teams)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: t.color, radius: 10),
                  title: Text(t.name),
                  subtitle: Text(
                    _spawns.containsKey(t.id) ? '설정됨' : '미설정',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await _live.setSpawn(
                            teamId: t.id,
                            point: _map.camera.center,
                          );
                          _showToast('${t.name} 리스폰 설정');
                        },
                        child: const Text('중앙에 지정'),
                      ),
                      if (_spawns.containsKey(t.id))
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _live.clearSpawn(t.id),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              const ListTile(title: Text('라운드 운영')),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.orange),
                title: const Text('라운드 초기화'),
                subtitle: const Text('사망 해제 · 적 표식과 기록 삭제 · 거점 중립으로'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _resetRound();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('전적 보기'),
                subtitle: const Text('사망 집계와 거점 변경 횟수'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openStats();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('전체 기록'),
                subtitle: const Text('누가 언제 사망했고 거점을 누가 바꿨는지'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openLog();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.download_for_offline),
                title: const Text('지도 미리 받기'),
                subtitle: const Text('통신이 끊겨도 지도가 보이도록 저장'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _downloadTiles();
                },
              ),
              const Divider(),
              const ListTile(
                title: Text('필드 프리셋'),
                subtitle: Text('저장해두면 다음에 만드는 방에서도 그대로 불러옵니다'),
              ),
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('현재 배치를 프리셋으로 저장'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _savePreset();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('프리셋 불러오기'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _loadPreset();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 경계는 십자선을 옮겨가며 꼭짓점을 하나씩 찍어서 만든다.
  /// 화면에 손가락으로 그리는 방식은 뛰면서 쓰기엔 부정확하다.
  Future<void> _addBoundaryPoint() async {
    if (!_mapReady) return;
    final next = [..._boundary, _map.camera.center];
    await _live.setBoundary(next);
    _showToast('경계 점 ${next.length}개');
  }

  Future<void> _undoBoundaryPoint() async {
    if (_boundary.isEmpty) return;
    final next = _boundary.sublist(0, _boundary.length - 1);
    if (next.isEmpty) {
      await _live.clearBoundary();
    } else {
      await _live.setBoundary(next);
    }
    _showToast('경계 점 ${next.length}개');
  }

  /// 경기당 15분씩 여러 판을 치르므로, 판이 끝나면 상태를 되돌려야 한다.
  /// 거점·리스폰·경계 같은 필드 배치는 그대로 두고 전투 결과만 지운다.
  Future<void> _resetRound() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('라운드 초기화'),
        content: const Text(
          '전원 사망 표시를 풀고, 적 표식과 기록을 지우고, 거점을 중립으로 되돌립니다.\n'
          '거점 위치·리스폰·경계는 그대로 유지됩니다.\n\n'
          '전적을 남기려면 먼저 전적 보기에서 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _live.resetRound(memberUids: _members.map((m) => m.uid).toList());
    _seenEvents.clear();
    _eventsPrimed = false;
    if (mounted) _showToast('라운드 초기화 완료');
  }

  /// 판이 끝나고 팀원들에게 보여줄 숫자.
  Future<void> _openStats() async {
    final log = await _live.fullLog();
    if (!mounted) return;
    final stats = buildStats(events: log, teams: _teams);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('전적'),
                subtitle: Text(
                  stats.duration == Duration.zero
                      ? '기록 없음'
                      : '경기 시간 ${stats.duration.inMinutes}분 '
                          '${stats.duration.inSeconds % 60}초',
                ),
              ),
              const Divider(height: 1),
              if (stats.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('아직 집계할 기록이 없습니다.'),
                )
              else ...[
                _statHeader('분대별 사망 (총 ${stats.totalDeaths}명)'),
                for (final e in ranked(stats.deathsBySquad))
                  _statRow(e.key, '${e.value}명'),
                _statHeader('개인별 사망'),
                for (final e in ranked(stats.deathsByPlayer))
                  _statRow(e.key, '${e.value}회'),
                _statHeader('거점 상태 변경 (총 ${stats.objectiveChanges}회)'),
                for (final e in ranked(stats.changesByPlayer))
                  _statRow(e.key, '${e.value}회'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statHeader(String title) => Container(
        color: Colors.white10,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _statRow(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  /// 산이나 외곽 지역은 통신이 끊기는 구간이 있다. 필드 일대를 미리 받아둔다.
  Future<void> _downloadTiles() async {
    const radius = 1200.0;
    const minZoom = 13;
    const maxZoom = 18;

    final count = TileCache.instance.estimateTileCount(
      center: _basePoint,
      radiusMeters: radius,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    final start = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_source.label} 미리 받기'),
        content: Text(
          '기준점 반경 약 ${(radius / 1000).toStringAsFixed(1)}km를 저장합니다.\n'
          '타일 약 $count장 · 몇 분 걸릴 수 있습니다.\n\n'
          '와이파이에서 미리 받아두세요. 지도를 바꿔 쓸 계획이면 지도별로 각각 받아야 합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('받기'),
          ),
        ],
      ),
    );
    if (start != true || !mounted) return;

    var cancelled = false;
    final progress =
        ValueNotifier<({int done, int total})>((done: 0, total: count));

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지도 받는 중'),
        content: ValueListenableBuilder<({int done, int total})>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value.total == 0 ? 0 : value.done / value.total,
              ),
              const SizedBox(height: 12),
              Text('${value.done} / ${value.total}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('중단'),
          ),
        ],
      ),
    ));

    await TileCache.instance.downloadArea(
      sourceId: _source.id,
      urlTemplate: _source.urlTemplate,
      center: _basePoint,
      radiusMeters: radius,
      minZoom: minZoom,
      maxZoom: maxZoom,
      onProgress: (done, total) => progress.value = (done: done, total: total),
      isCancelled: () => cancelled,
    );

    final bytes = await TileCache.instance.cachedBytes(_source.id);
    if (!mounted) return;
    if (!cancelled) Navigator.of(context).pop();
    _showToast(
      cancelled
          ? '중단됨 (받은 만큼은 저장됨)'
          : '저장 완료 · ${(bytes / 1024 / 1024).toStringAsFixed(1)}MB',
    );
  }

  /// 운영자용 전체 기록. 시각까지 찍어서 사후에 되짚을 수 있게 한다.
  Future<void> _openLog() async {
    final log = await _live.fullLog();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (context, controller) => Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('전체 기록'),
                subtitle: Text('${log.length}건'),
              ),
              const Divider(height: 1),
              Expanded(
                child: log.isEmpty
                    ? const Center(child: Text('아직 기록이 없습니다'))
                    : ListView.builder(
                        controller: controller,
                        itemCount: log.length,
                        itemBuilder: (context, i) {
                          final e = log[i];
                          final time =
                              DateTime.fromMillisecondsSinceEpoch(e.timestamp);
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              switch (e.type) {
                                EventType.objective => Icons.flag,
                                EventType.death => Icons.person_off,
                                EventType.revive => Icons.refresh,
                              },
                              size: 18,
                              color: switch (e.type) {
                                EventType.objective => Colors.amber,
                                EventType.death => Colors.redAccent,
                                EventType.revive => Colors.greenAccent,
                              },
                            ),
                            title: Text(e.message),
                            trailing: Text(
                              clockTime(time),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addObjective() async {
    if (!_mapReady) return;
    final name = await _promptText(
      title: '거점 이름',
      hint: 'A, B, 전망대 …',
      initial: String.fromCharCode(65 + _objectives.length),
      maxLength: 4,
    );
    if (name == null || name.isEmpty) return;
    await _live.addObjective(
      name: name,
      point: _map.camera.center,
      callsign: _me?.callsign ?? '?',
    );
    _showToast('거점 $name 추가');
  }

  Future<void> _savePreset() async {
    final name = await _promptText(
      title: '프리셋 이름',
      hint: '경기장 1안',
      maxLength: 20,
    );
    if (name == null || name.isEmpty) return;

    final teamNameById = {for (final t in _teams) t.id: t.name};
    await _live.savePreset(FieldPreset(
      id: '',
      name: name,
      createdBy: _uid,
      objectives: [
        for (final o in _objectives) (name: o.name, point: o.point),
      ],
      spawns: {
        for (final e in _spawns.entries)
          if (teamNameById[e.key] != null)
            teamNameById[e.key]!: e.value.point,
      },
      boundary: _boundary,
    ));
    _showToast('프리셋 저장됨: $name');
  }

  Future<void> _loadPreset() async {
    final presets = await _live.loadPresets();
    if (!mounted) return;
    if (presets.isEmpty) {
      _showToast('저장된 프리셋이 없습니다');
      return;
    }

    final picked = await _sheet<FieldPreset>(
      title: '프리셋 불러오기',
      items: [
        for (final p in presets)
          (
            icon: Icons.folder,
            color: Colors.amber,
            title: p.name,
            subtitle: '거점 ${p.objectives.length}개 · 리스폰 ${p.spawns.length}개'
                '${p.boundary.length >= 3 ? ' · 경계 있음' : ''}',
            selected: false,
            value: p,
          ),
      ],
    );
    if (picked == null) return;

    await _live.applyPreset(
      preset: picked,
      teamIdByName: {for (final t in _teams) t.name: t.id},
      callsign: _me?.callsign ?? '?',
    );
    _showToast('${picked.name} 적용됨');
  }

  // ---- 명단 ----

  Future<void> _openRoster() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              const ListTile(title: Text('분대원 현황')),
              const Divider(height: 1),
              for (final team in _teams) ...[
                _sectionHeader(team.name, team.color),
                for (final m in _members.where((m) => m.teamId == team.id))
                  _rosterTile(m, team),
              ],
              if (_members.any((m) => m.teamId == null)) ...[
                _sectionHeader('미배정', Colors.blueGrey),
                for (final m in _members.where((m) => m.teamId == null))
                  _rosterTile(m, null),
              ],
              const Divider(),
              const ListTile(title: Text('최근 상황')),
              for (final e in _events.take(15))
                ListTile(
                  dense: true,
                  leading: Icon(
                    switch (e.type) {
                      EventType.objective => Icons.flag,
                      EventType.death => Icons.close,
                      EventType.revive => Icons.refresh,
                    },
                    size: 18,
                  ),
                  title: Text(e.message),
                  subtitle: Text(
                    ago(DateTime.fromMillisecondsSinceEpoch(e.timestamp)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) => Container(
        color: color.withValues(alpha: 0.25),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _rosterTile(Member m, Team? team) {
    final pos = _positions[m.uid];
    final myPos = _positions[_uid];
    final dead = pos?.dead ?? false;

    String subtitle;
    if (pos == null) {
      subtitle = '위치 없음';
    } else {
      final age = pos.ageFrom(_now);
      final parts = <String>[
        age.inSeconds < 5 ? '방금' : '${age.inSeconds}초 전',
        '±${pos.accuracy.round()}m',
      ];
      if (myPos != null && m.uid != _uid) {
        parts.insert(0, '${_distance(myPos.point, pos.point).round()}m');
      }
      subtitle = parts.join(' · ');
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 10,
        backgroundColor: dead ? Colors.grey : (team?.color ?? Colors.blueGrey),
        child: dead
            ? const Icon(Icons.close, size: 12, color: Colors.white)
            : null,
      ),
      title: Text(
        m.callsign + (m.uid == _uid ? ' (나)' : ''),
        style: TextStyle(decoration: dead ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text(subtitle),
      onTap: pos == null
          ? null
          : () {
              Navigator.of(context).pop();
              _map.move(pos.point, 17);
            },
    );
  }

  // ---- 지도 레이어 ----

  List<Marker> _memberMarkers() {
    final markers = <Marker>[];
    final mySquad = _me?.teamId;
    for (final m in _members) {
      if (m.spectator) continue;
      final pos = _positions[m.uid];
      if (pos == null) continue;
      final team = _teamOf(m);
      final stale = pos.ageFrom(_now) > staleAfter;
      final heading = pos.heading == null ? null : pos.heading! + _mapRotation;

      markers.add(Marker(
        point: pos.point,
        width: 72,
        height: 72,
        rotate: false,
        child: Opacity(
          opacity: stale ? 0.4 : 1,
          child: HeadingMarker(
            color: team?.color ?? Colors.blueGrey,
            headingDegrees: heading,
            label: m.uid == _uid ? '나' : m.callsign,
            dead: pos.dead,
            sameSquad: mySquad != null && m.teamId == mySquad,
            size: 72,
          ),
        ),
      ));
    }
    return markers;
  }

  List<Marker> _markMarkers() {
    return _marks.where((mk) => mk.ageFrom(_now) < markLifetime).map((mk) {
      final remaining = markLifetime - mk.ageFrom(_now);
      final fade = (remaining.inMilliseconds / markLifetime.inMilliseconds)
          .clamp(0.3, 1.0)
          .toDouble();
      return Marker(
        point: mk.point,
        width: 26,
        height: 26,
        rotate: false,
        child: Opacity(
          opacity: fade,
          child: GestureDetector(
            onLongPress: () => _live.removeMark(mk.id),
            child: Icon(
              markIcon(mk.type),
              color: hexColor(mk.type.colorHex),
              size: 20,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _deathPins() => _events
      .where((e) =>
          e.type == EventType.death &&
          e.point != null &&
          e.ageFrom(_now) < deathPinLifetime)
      .map((e) => Marker(
            point: e.point!,
            width: 26,
            height: 26,
            rotate: false,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: const Icon(
                Icons.person_off,
                color: Colors.white,
                size: 14,
              ),
            ),
          ))
      .toList();

  List<Marker> _objectiveMarkers() => _objectives
      .map((o) => Marker(
            point: o.point,
            width: 44,
            height: 44,
            rotate: false,
            child: GestureDetector(
              onTap: () => _changeOwner(o),
              child: ObjectiveMarker(
                name: o.name,
                color: hexColor(o.owner.colorHex),
              ),
            ),
          ))
      .toList();

  List<Marker> _spawnMarkers() {
    final markers = <Marker>[];
    for (final entry in _spawns.entries) {
      final team = _teams.where((t) => t.id == entry.key).firstOrNull;
      markers.add(Marker(
        point: entry.value.point,
        width: 54,
        height: 46,
        rotate: false,
        child: SpawnMarker(
          teamName: team?.name ?? '?',
          color: team?.color ?? Colors.white,
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final deadUids = {
      for (final e in _positions.entries)
        if (e.value.dead) e.key,
    };
    final statuses = buildTeamStatuses(
      teams: _teams,
      members: _members.where((m) => !m.spectator).toList(),
      deadUids: deadUids,
    );

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _basePoint,
              initialZoom: 15,
              maxZoom: 21,
              // 확대할 때 손가락이 조금만 틀어져도 지도가 돌아가서 방향 감각을
              // 잃는다. 회전은 나침반 버튼으로만 하고 제스처에서는 뺀다.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _mapReady = true;
                _moveToBase();
              },
              onPositionChanged: (camera, _) {
                if (camera.rotation != _mapRotation) {
                  setState(() => _mapRotation = camera.rotation);
                }
              },
            ),
            children: [
              TileLayer(
                key: ValueKey(_source.id),
                urlTemplate: _source.urlTemplate,
                userAgentPackageName: 'com.ocy.tacmap',
                maxNativeZoom: _source.maxZoom,
                // 미리 받아둔 타일이 있으면 통신이 끊겨도 지도가 보인다.
                tileProvider: CachedTileProvider(sourceId: _source.id),
              ),
              if (_boundary.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _boundary,
                      color: Colors.amber.withValues(alpha: 0.10),
                      borderColor: Colors.amberAccent,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: [
                ..._deathPins(),
                ..._spawnMarkers(),
                ..._objectiveMarkers(),
                ..._markMarkers(),
                ..._memberMarkers(),
              ]),
            ],
          ),

          const IgnorePointer(child: Center(child: _Crosshair())),

          // 홀드 게이지는 화면 한가운데. 버튼 위에 그리면 손가락에 가린다.
          if (_holdProgress > 0)
            HoldGauge(
              progress: _holdProgress,
              label: _amDead ? '복귀 처리' : '사망 처리',
              color: _amDead ? Colors.greenAccent : Colors.redAccent,
              seconds: 3,
            ),

          SafeArea(
            child: Stack(
              children: [
                // 인원 현황: 위쪽 가운데. 지도 위지만 얇아서 시야를 거의 안 먹는다.
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: TeamStatusBar(
                      statuses: statuses,
                      onTap: _openRoster,
                    ),
                  ),
                ),

                // 알림: 인원 현황 바로 아래 중앙. 버튼을 가리지 않는다.
                if (_toast != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 56),
                      child: _Toast(message: _toast!),
                    ),
                  ),

                // 왼쪽: 전투 조작
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LeftPanel(
                    dead: _amDead,
                    markType: _markType,
                    onHoldProgress: (v) => setState(() => _holdProgress = v),
                    onHoldDead: _toggleDead,
                    onMark: _placeMark,
                    onHoldMark: _pickMarkType,
                    onObjectives: _openObjectiveList,
                  ),
                ),

                // 오른쪽: 지도 조작
                Align(
                  alignment: Alignment.centerRight,
                  child: _RightPanel(
                    heading: _heading,
                    northUp: _orientation == MapOrientation.northUp,
                    isHost: _isHost,
                    onTapSource: _openSourceSheet,
                    onTapCompass: _toggleOrientation,
                    onMyLocation: () {
                      final me = _positions[_uid];
                      if (me != null) _map.move(me.point, 17);
                    },
                    onBase: _moveToBase,
                    onHoldBase: _setBasePoint,
                    onSetup: _openFieldSetup,
                    onArena: _pickArena,
                    arenaName: _arena.name,
                  ),
                ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: _StatusLine(
                    code: widget.code,
                    sharing: _sharing,
                    attribution: _source.attribution,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openObjectiveList() async {
    if (_objectives.isEmpty) {
      _showToast(_isHost ? '거점이 없습니다. 오른쪽 설정에서 추가하세요' : '등록된 거점이 없습니다');
      return;
    }
    final picked = await _sheet<Objective>(
      title: '거점 현황',
      items: [
        for (final o in _objectives)
          (
            icon: Icons.circle,
            color: hexColor(o.owner.colorHex),
            title: '${o.name} · ${o.owner.label}',
            subtitle:
                '${o.byCallsign} · ${ago(DateTime.fromMillisecondsSinceEpoch(o.updatedAt))}',
            selected: false,
            value: o,
          ),
      ],
    );
    if (picked != null) await _changeOwner(picked);
  }

  Future<void> _setBasePoint() async {
    final input = await _promptText(
      title: '${_arena.name} 기준 좌표',
      hint: '37.92, 128.33',
      initial: '${_basePoint.latitude}, ${_basePoint.longitude}',
      maxLength: 40,
    );
    if (input == null || input.isEmpty) return;

    final point = parseLatLng(input);
    if (point == null) {
      _showToast('좌표 형식이 아닙니다');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_arena.latKey, point.latitude);
    await prefs.setDouble(_arena.lngKey, point.longitude);
    if (!mounted) return;
    setState(() => _basePoint = point);
    _moveToBase();
    _showToast('${_arena.name} 기준점 저장됨');
  }

  // ---- 공용 다이얼로그 ----

  Future<T?> _sheet<T>({
    required String title,
    required List<
            ({
              IconData icon,
              Color color,
              String title,
              String? subtitle,
              bool selected,
              T value,
            })>
        items,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(title)),
              const Divider(height: 1),
              for (final item in items)
                ListTile(
                  leading: Icon(item.icon, color: item.color),
                  title: Text(item.title),
                  subtitle:
                      item.subtitle == null ? null : Text(item.subtitle!),
                  trailing: item.selected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(item.value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String? initial,
    int maxLength = 12,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
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
}

// ---- 헬퍼 ----

Color hexColor(String hex) =>
    Color(int.parse(hex.replaceFirst('#', 'ff'), radix: 16));

IconData markIcon(MarkType type) => switch (type) {
      MarkType.enemy => Icons.crisis_alert,
      MarkType.sniper => Icons.center_focus_strong,
      MarkType.danger => Icons.warning,
      MarkType.rally => Icons.groups,
    };

/// 기록에는 상대 시간보다 실제 시각이 낫다. 무전 기록과 맞춰봐야 하기 때문.
String clockTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}:'
    '${time.second.toString().padLeft(2, '0')}';

String ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 10) return '방금';
  if (diff.inMinutes < 1) return '${diff.inSeconds}초 전';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  return '${diff.inHours}시간 전';
}

/// "37.92, 128.33" 또는 "37.92 128.33"을 좌표로 바꾼다.
/// 한국 범위를 벗어나면 오타로 보고 거부한다.
LatLng? parseLatLng(String input) {
  final parts =
      input.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  if (lat < 33 || lat > 39 || lng < 124 || lng > 132) return null;
  return LatLng(lat, lng);
}

/// 방위각을 8방위 한글로. 무전으로 부를 때 숫자보다 빠르다.
String compassLabel(double degrees) {
  const names = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
  return names[((degrees % 360) / 45).round() % 8];
}

// ---- 화면 조각 ----

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(painter: _CrosshairPainter()),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(c.dx - 14, c.dy), Offset(c.dx - 4, c.dy), paint);
    canvas.drawLine(Offset(c.dx + 4, c.dy), Offset(c.dx + 14, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - 14), Offset(c.dx, c.dy - 4), paint);
    canvas.drawLine(Offset(c.dx, c.dy + 4), Offset(c.dx, c.dy + 14), paint);
    canvas.drawCircle(c, 2, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// 왼쪽 세로 패널: 전투 중 실제로 누르는 버튼들.
class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.dead,
    required this.markType,
    required this.onHoldProgress,
    required this.onHoldDead,
    required this.onMark,
    required this.onHoldMark,
    required this.onObjectives,
  });

  final bool dead;
  final MarkType markType;
  final ValueChanged<double> onHoldProgress;
  final VoidCallback onHoldDead;
  final VoidCallback onMark;
  final VoidCallback onHoldMark;
  final VoidCallback onObjectives;

  @override
  Widget build(BuildContext context) {
    // dp는 기기 밀도와 무관한 단위라 물리적 크기는 어디서나 비슷하지만,
    // 화면 높이는 기기마다 달라서 남는 높이에 맞춰 잡고 최소/최대만 고정한다.
    return LayoutBuilder(
      builder: (context, constraints) {
        // 사망 : 적 : 거점 = 1 : 1.5 : 1.5 → 합이 4배
        final base = ((constraints.maxHeight - 24) / 4).clamp(60.0, 104.0);
        final actionSize = base * 1.5;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            // 위 / 가운데 / 아래로 떨어뜨려서 손이 가는 위치를 고정한다.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoldButton(
                glyph: dead ? '\u{1F503}' : '\u{1F480}',
                label: dead ? '복귀' : '사망',
                background: dead
                    ? const Color(0xFF2E4A32)
                    : const Color(0xFF3A3A3A),
                size: base,
                onProgress: onHoldProgress,
                onHoldComplete: onHoldDead,
              ),
              _BigButton(
                icon: markIcon(markType),
                label: markType.label,
                hint: '길게=종류',
                color: hexColor(markType.colorHex),
                size: actionSize,
                onTap: onMark,
                onLongPress: onHoldMark,
              ),
              _BigButton(
                icon: Icons.flag,
                label: '거점',
                color: Colors.blueGrey,
                size: actionSize,
                onTap: onObjectives,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 오른쪽 세로 패널: 지도를 다루는 버튼들.
class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.heading,
    required this.northUp,
    required this.isHost,
    required this.onTapSource,
    required this.onTapCompass,
    required this.onMyLocation,
    required this.onBase,
    required this.onHoldBase,
    required this.onSetup,
    required this.onArena,
    required this.arenaName,
  });

  final double? heading;
  final bool northUp;
  final bool isHost;
  final VoidCallback onTapSource;
  final VoidCallback onTapCompass;
  final VoidCallback onMyLocation;
  final VoidCallback onBase;
  final VoidCallback onHoldBase;
  final VoidCallback onSetup;
  final VoidCallback onArena;
  final String arenaName;

  @override
  Widget build(BuildContext context) {
    final text =
        heading == null ? '--' : '${heading!.round()}° ${compassLabel(heading!)}';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RoundButton(
            icon: northUp ? Icons.explore : Icons.navigation,
            color: northUp ? Colors.white : Colors.amberAccent,
            caption: text,
            onTap: onTapCompass,
          ),
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.layers,
            color: Colors.white,
            caption: '지도 변경',
            onTap: onTapSource,
          ),
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.my_location,
            color: Colors.white,
            caption: '내 위치',
            onTap: onMyLocation,
          ),
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.stadium,
            color: Colors.white,
            caption: arenaName,
            onTap: onArena,
          ),
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.place,
            color: Colors.white,
            caption: '기준점',
            onTap: onBase,
            onLongPress: onHoldBase,
          ),
          if (isHost) ...[
            const SizedBox(height: 8),
            _RoundButton(
              icon: Icons.settings,
              color: Colors.amberAccent,
              caption: '필드 설정',
              onTap: onSetup,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.caption,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final Color color;
  final String caption;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                caption,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.size,
    this.hint,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: size * 0.32),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.code,
    required this.sharing,
    required this.attribution,
  });

  final String code;
  final bool sharing;
  final String attribution;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sharing ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            size: 12,
            color: sharing ? Colors.lightGreenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 6),
          Text(
            '방 $code · $attribution',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
