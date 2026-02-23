import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../models/jog_route.dart';
import '../services/route_painter.dart';

// ─────────────────────────────────────────────
// MapScreen
// 네이버 지도를 표시하는 메인 화면.
// - 내 위치(Blue Dot) 활성화
// - 초기 카메라: 서울 시청 (37.5666, 126.9784)
// - 조깅 경로(Polyline) 그리기를 위한 확장 포인트 포함
// ─────────────────────────────────────────────
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // 지도 컨트롤러 (지도가 준비된 후 사용 가능)
  NaverMapController? _mapController;

  // 조깅 경로 모델 (Polyline 확장 포인트)
  final JogRoute _currentRoute = JogRoute();

  // 조깅 중 여부
  bool _isRunning = false;

  // 위치 스트림 구독 (조깅 중일 때만 활성화)
  StreamSubscription<Position>? _positionStreamSubscription;

  // 서울 시청 초기 좌표
  static const NLatLng _seoulCityHall = NLatLng(37.5666, 126.9784);

  // ─────────────────────────────────────
  // 지도 초기 옵션 설정
  // ─────────────────────────────────────
  NaverMapViewOptions get _mapOptions => const NaverMapViewOptions(
    // 초기 카메라 위치: 서울 시청, 줌 레벨 15
    initialCameraPosition: NCameraPosition(target: _seoulCityHall, zoom: 15),
    // 내 위치(Blue Dot) 활성화
    locationButtonEnable: true,
    // 실내 지도 비활성화 (조깅 앱 특성상 야외 중심)
    indoorEnable: false,
    // 지도 타입: 기본
    mapType: NMapType.basic,
    // 스크롤/줌 제스처 허용
    scrollGesturesEnable: true,
    zoomGesturesEnable: true,
    // 나침반, 축척 바 표시
    compassEnable: true,
    scaleBarEnable: true,
  );

  // ─────────────────────────────────────
  // 지도 준비 완료 콜백
  // ─────────────────────────────────────
  Future<void> _onMapReady(NaverMapController controller) async {
    _mapController = controller;
    debugPrint('[MapScreen] ✅ 지도 준비 완료');

    // 내 위치 레이어(Blue Dot) 활성화
    controller.setLocationTrackingMode(NLocationTrackingMode.follow);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────
  // 조깅 시작/종료 토글
  // ─────────────────────────────────────
  void _toggleRunning() {
    setState(() {
      _isRunning = !_isRunning;

      if (_isRunning) {
        _currentRoute.start();
        debugPrint('[MapScreen] 🏃 조깅 시작');

        // 위치 스트림 시작
        _positionStreamSubscription =
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 5, // 5미터 이동 시마다 갱신
              ),
            ).listen((Position position) {
              final latLng = NLatLng(position.latitude, position.longitude);

              setState(() {
                _currentRoute.addPoint(latLng);
              });

              // 지도에 경로 그리기 (RoutePainter가 구현되어 있다고 가정)
              RoutePainter.drawRoute(_mapController!, _currentRoute);
            });
      } else {
        _currentRoute.stop();
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
        debugPrint(
          '[MapScreen] 🛑 조깅 종료. 총 거리: ${_currentRoute.totalDistanceKm.toStringAsFixed(2)} km',
        );
        // TODO: 경로 저장 로직 추가
      }
    });
  }

  // ─────────────────────────────────────
  // 카메라를 내 위치로 이동
  // ─────────────────────────────────────
  Future<void> _moveToMyLocation() async {
    if (_mapController == null) return;
    _mapController!.setLocationTrackingMode(NLocationTrackingMode.follow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('조깅 경로 앱'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: '내 위치로 이동',
            onPressed: _moveToMyLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── 네이버 지도 ──
          NaverMap(
            options: _mapOptions,
            onMapReady: _onMapReady,
            onMapTapped: (point, latLng) {
              debugPrint('[MapScreen] 지도 탭: $latLng');
            },
          ),

          // ── 조깅 정보 오버레이 (조깅 중일 때만 표시) ──
          if (_isRunning)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _RunningInfoCard(route: _currentRoute),
            ),
        ],
      ),

      // ── 조깅 시작/종료 버튼 ──
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleRunning,
        icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
        label: Text(_isRunning ? '조깅 종료' : '조깅 시작'),
        backgroundColor: _isRunning ? Colors.red : Colors.green,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ─────────────────────────────────────────────
// 조깅 중 정보 표시 카드
// ─────────────────────────────────────────────
class _RunningInfoCard extends StatelessWidget {
  final JogRoute route;

  const _RunningInfoCard({required this.route});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _InfoItem(
              label: '거리',
              value: '${route.totalDistanceKm.toStringAsFixed(2)} km',
              icon: Icons.straighten,
            ),
            _InfoItem(
              label: '시간',
              value: route.elapsedTimeFormatted,
              icon: Icons.timer,
            ),
            _InfoItem(
              label: '포인트',
              value: '${route.points.length}',
              icon: Icons.location_on,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.green),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
