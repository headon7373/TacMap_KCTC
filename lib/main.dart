import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/start_screen.dart';
import 'services/room_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 플레이트 캐리어에 눕혀 다는 것을 전제로 가로 모드로 고정한다.
  // 가로에서는 지도를 넓게 쓰고 조작 버튼을 양옆에 둘 수 있다.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const TacMapApp());
}

class TacMapApp extends StatelessWidget {
  const TacMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TacMap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A5D3A),
          brightness: Brightness.dark,
        ),
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Firebase 초기화와 익명 로그인을 끝낸 뒤에야 앱 화면을 띄운다.
/// 이 단계가 끝나면 사용자마다 고유 uid가 생겨서 "누가 보냈는지"를 구분할 수 있다.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<RoomService> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _signIn();
  }

  Future<RoomService> _signIn() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return RoomService();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoomService>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 16),
                    const Text('서버에 연결하지 못했습니다.'),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => setState(() => _ready = _signIn()),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return StartScreen(service: snapshot.data!);
      },
    );
  }
}
