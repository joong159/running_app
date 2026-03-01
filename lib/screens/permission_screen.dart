import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatefulWidget {
  final VoidCallback onAllPermissionsGranted;

  const PermissionScreen({super.key, required this.onAllPermissionsGranted});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // 이미 권한이 있는지 확인
    final locStatus = await Permission.locationWhenInUse.status;
    if (locStatus.isGranted) {
      widget.onAllPermissionsGranted();
    }
  }

  Future<void> _requestPermissions() async {
    // 1. 위치 권한 요청 (필수)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.locationWhenInUse,
      Permission.notification,
      // Permission.ignoreBatteryOptimizations, // 필요 시 주석 해제 (백그라운드 최적화 제외)
    ].request();

    // 위치 권한이 허용되었으면 다음 화면으로 진행
    if (statuses[Permission.locationWhenInUse]!.isGranted) {
      widget.onAllPermissionsGranted();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('원활한 러닝 기록을 위해 위치 권한이 꼭 필요합니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 다크 테마 배경
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                '가온길 이용을 위해\n권한 허용이 필요합니다',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '정확한 러닝 기록 측정과 안내를 위해\n아래 권한들을 허용해 주세요.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 40),

              _buildPermissionItem(
                icon: Icons.location_on_outlined,
                title: '위치 정보 (필수)',
                description: '실시간 러닝 경로, 속도, 거리를 정확하게 기록하기 위해 사용합니다.',
              ),
              const SizedBox(height: 24),
              _buildPermissionItem(
                icon: Icons.notifications_active_outlined,
                title: '알림 (선택)',
                description: '러닝 중 음성 안내와 주요 알림을 받기 위해 사용합니다.',
              ),
              const SizedBox(height: 24),
              _buildPermissionItem(
                icon: Icons.battery_std,
                title: '백그라운드 실행',
                description: '화면이 꺼져도 끊김 없이 기록하기 위해 배터리 최적화를 제외할 수 있습니다.',
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCCFF00), // 네온 라임 포인트
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '동의하고 시작하기',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFCCFF00), size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
