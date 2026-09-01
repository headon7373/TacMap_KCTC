import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/room_service.dart';
import 'lobby_screen.dart';

/// 첫 화면: 콜사인을 입력하고 방을 만들거나 코드로 참가한다.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.service});

  final RoomService service;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _callsign = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreCallsign();
  }

  @override
  void dispose() {
    _callsign.dispose();
    _code.dispose();
    super.dispose();
  }

  /// 매번 이름을 다시 치지 않도록 마지막 콜사인을 기억해 둔다.
  Future<void> _restoreCallsign() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('callsign');
    if (saved != null && mounted) {
      _callsign.text = saved;
    }
  }

  Future<void> _run(Future<String> Function(String callsign) action) async {
    final callsign = _callsign.text.trim();
    if (callsign.isEmpty) {
      setState(() => _error = '콜사인을 입력하세요.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final code = await action(callsign);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('callsign', callsign);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LobbyScreen(service: widget.service, code: code),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TacMap')),
      // 가로 모드에서는 키보드가 올라오면 세로 공간이 거의 없다. 반드시 스크롤 가능해야 한다.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _callsign,
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '콜사인',
                helperText: '무전에서 부르는 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run((c) => widget.service.createRoom(callsign: c)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text('방 만들기'),
            ),
            const Divider(height: 40),
            TextField(
              controller: _code,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '참가 코드 6자리',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run((c) async {
                        final code = _code.text.trim();
                        await widget.service
                            .joinRoom(code: code, callsign: c);
                        return code;
                      }),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text('코드로 참가'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
