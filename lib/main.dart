import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/map_screen.dart';
import 'services/location_service.dart';

// ─────────────────────────────────────────────
// 앱 진입점
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initNaverMapSdk();

  runApp(const RunningApp());
}

/// 네이버 지도 SDK 초기화
/// 401 인증 실패 시 debugPrint로 에러 메시지 출력
Future<void> _initNaverMapSdk() async {
  try {
    await NaverMapSdk.instance.initialize(
      clientId: 'e4er7uvr2b', // 네이버 클라우드 플랫폼 Client ID
      onAuthFailed: (error) {
        debugPrint('[NaverMap] ❌ 인증 실패 (401): $error');
        debugPrint(
          '[NaverMap] Client ID 또는 앱 패키지명(com.example.running_app)을 확인하세요.',
        );
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
      title: '조깅 경로 앱',
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

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
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

    if (!_permissionGranted) {
      return _PermissionDeniedScreen(
        onRetry: () {
          setState(() => _isLoading = true);
          _requestLocationPermission();
        },
      );
    }

    return const MapScreen();
  }
}

// ─────────────────────────────────────────────
// 위치 권한 거부 시 안내 화면
// ─────────────────────────────────────────────
class _PermissionDeniedScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _PermissionDeniedScreen({required this.onRetry});

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
