import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/map_screen.dart';
import 'screens/login_screen.dart';
import 'services/location_service.dart';
import 'services/auth_service.dart';

// ─────────────────────────────────────────────
// 앱 진입점
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const RunningApp());
}

/// 네이버 지도 SDK 초기화
Future<void> _initNaverMapSdk() async {
  try {
    // 초기화 전에 이 문구가 터미널에 찍히는지 확인용
    debugPrint('[NaverMap] SDK 초기화 시작...');

    await NaverMapSdk.instance.initialize(
      onAuthFailed: (ex) {
        // 예제 코드의 상세 에러 처리 로직 적용
        if (ex is NQuotaExceededException) {
          debugPrint('[NaverMap] ❌ 사용량 초과: ${ex.message}');
        } else if (ex is NUnauthorizedClientException ||
            ex is NClientUnspecifiedException ||
            ex is NAnotherAuthFailedException) {
          debugPrint('[NaverMap] ❌ 인증 실패: $ex');
        } else {
          debugPrint('[NaverMap] ❌ 알 수 없는 인증 오류: $ex');
        }
      },
    );

    debugPrint('[NaverMap] ✅ SDK 초기화 성공');
  } catch (e) {
    debugPrint('[NaverMap] ❌ SDK 초기화 중 예외 발생: $e');
  }
}

// ─────────────────────────────────────────────
// 루트 앱 위젯
// ─────────────────────────────────────────────
class RunningApp extends StatelessWidget {
  const RunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가온길', // ✅ 앱 타이틀도 '가온길'로 수정했습니다.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const AppEntryPoint(),
    );
  }
}

// ─────────────────────────────────────────────
// 위치 권한 요청 → MapScreen으로 이동
// ─────────────────────────────────────────────
class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  bool _permissionGranted = false;
  bool _isLoading = true;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. 네이버 지도 SDK 초기화
    await _initNaverMapSdk();

    // 2. 위치 권한 요청
    final granted = await LocationService.requestPermission();
    if (mounted) {
      setState(() {
        _permissionGranted = granted;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 3. 인증 상태에 따라 화면 분기
    return StreamBuilder<User?>(
      stream: _authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 4. 위치 권한 확인
        if (!_permissionGranted) {
          return _PermissionDeniedScreen(
            onRetry: () {
              setState(() => _isLoading = true);
              _initializeApp();
            },
          );
        }

        // 5. 로그인 여부에 따라 화면 결정
        if (snapshot.hasData) {
          return const MapScreen(); // 로그인 되어 있으면 MapScreen으로
        } else {
          return const LoginScreen(); // 로그인 안되어 있으면 LoginScreen으로
        }
      },
    );
  }
}

// ─────────────────────────────────────────────
// 위치 권한 거부 시 안내 화면
// ─────────────────────────────────────────────
class _PermissionDeniedScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _PermissionDeniedScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                '위치 권한이 필요합니다',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '조깅 경로 기록을 위해 위치 권한을 허용해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('권한 다시 요청'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('설정에서 직접 허용하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
