import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/room_service.dart';
import 'lobby_screen.dart';

/// 첫 화면: 내 정보를 넣고 방을 만들거나 코드로 참가한다.
/// 대회 명단이 등번호·소속대학·이름으로 오므로 그대로 받아둔다.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.service});

  final RoomService service;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _school = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _school.dispose();
    _code.dispose();
    super.dispose();
  }

  /// 매번 다시 치지 않도록 마지막 입력을 기억해 둔다.
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name.text = prefs.getString('callsign') ?? '';
      _number.text = prefs.getString('number') ?? '';
      _school.text = prefs.getString('school') ?? '';
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '이름을 입력하세요.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final code = await action();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('callsign', _name.text.trim());
      await prefs.setString('number', _number.text.trim());
      await prefs.setString('school', _school.text.trim());
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.map, size: 28),
                  const SizedBox(width: 10),
                  Text('TacMap', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: _field(_number, '등번호', keyboard: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_name, '이름')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_school, '소속대학')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Card(
                        title: '방 만들기',
                        subtitle: '내가 방장이 됩니다',
                        icon: Icons.add_circle,
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => widget.service.createRoom(
                                    callsign: _name.text.trim(),
                                    number: _number.text.trim(),
                                    school: _school.text.trim(),
                                  )),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('만들기'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Card(
                        title: '코드로 참가',
                        subtitle: '방장에게 받은 6자리',
                        icon: Icons.login,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _code,
                                maxLength: 6,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  letterSpacing: 6,
                                  fontWeight: FontWeight.bold,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  counterText: '',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                          final code = _code.text.trim();
                                          await widget.service.joinRoom(
                                            code: code,
                                            callsign: _name.text.trim(),
                                            number: _number.text.trim(),
                                            school: _school.text.trim(),
                                          );
                                          return code;
                                        }),
                                child: const Text('참가'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool keyboard = false,
  }) {
    return TextField(
      controller: controller,
      maxLength: 12,
      keyboardType: keyboard ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}
