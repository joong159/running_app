import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/map_screen.dart';
import 'screens/login_screen.dart';
import 'screens/permission_screen.dart'; // 📍 권한 화면 import
import 'screens/splash_screen.dart'; // 📍 스플래시 화면 import
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
  bool _isPermissionGranted = false;
  bool _isCheckingPermission = true;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. 초기화 및 스플래시 지연 (최소 2초 보여주기)
    await Future.wait([
      _initNaverMapSdk(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    // 2. 위치 권한 상태 확인 (요청은 PermissionScreen에서 함)
    final status = await Permission.locationWhenInUse.status;
    if (mounted) {
      setState(() {
        _isPermissionGranted = status.isGranted;
        _isCheckingPermission = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return const SplashScreen(); // 📍 로딩 대신 스플래시 화면 표시
    }

    // 3. 권한이 없으면 권한 안내 화면 표시
    if (!_isPermissionGranted) {
      return PermissionScreen(
        onAllPermissionsGranted: () {
          setState(() {
            _isPermissionGranted = true;
          });
        },
      );
    }

    // 3. 인증 상태에 따라 화면 분기
    return StreamBuilder<User?>(
      stream: _authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFCCFF00)),
            ),
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
