import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
  JogRoute _currentRoute = JogRoute();

  // 조깅 중 여부
  bool _isRunning = false;
  bool _isPaused = false;

  // 1. 데이터 변수 선언 (실시간 계산용)
  double _totalDistance = 0.0; // meters
  int _calories = 0; // kcal
  String _pace = "0'00''"; // min/km
  final Stopwatch _stopwatch = Stopwatch();
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // 위치 스트림 구독 (조깅 중일 때만 활성화)
  StreamSubscription<Position>? _positionStreamSubscription;

  // 서울 시청 초기 좌표
  static const NLatLng _seoulCityHall = NLatLng(37.5666, 126.9784);

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    // 1. permission_handler를 사용한 권한 체크 로직
    var status = await Permission.locationWhenInUse.status;

    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }

    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('위치 권한이 필요합니다.')));
      }
    }
  }

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

    // 1. 현재 위치 표시: 내 위치 추적 모드 활성화 (지도가 나를 따라다님)
    controller.setLocationTrackingMode(NLocationTrackingMode.follow);

    // 3. 추천 마커 찍기: 대진대학교 운동장 주변 (예시 좌표)
    _addRecommendedMarker(controller);
  }

  /// 추천 러닝 포인트 마커 추가
  void _addRecommendedMarker(NaverMapController controller) {
    final marker = NMarker(
      id: 'daejin_uni_track',
      position: const NLatLng(37.8747, 127.1552), // 대진대학교 좌표
      caption: const NOverlayCaption(text: "추천: 대진대 운동장"),
      iconTintColor: Colors.blueAccent, // 마커 색상 강조
    );

    controller.addOverlay(marker);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────
  // 운동 제어 (Start / Pause / Resume / Stop)
  // ─────────────────────────────────────
  void _startExercise() {
    setState(() {
      _isRunning = true;
      _isPaused = false;

      // 이전 경로 제거
      if (_mapController != null) {
        RoutePainter.clearRoute(_mapController!);
      }
      _currentRoute = JogRoute();
      _currentRoute.start();

      // 변수 초기화
      _totalDistance = 0.0;
      _calories = 0;
      _pace = "0'00''";
      _elapsed = Duration.zero;
      _stopwatch.reset();
      _stopwatch.start();

      // 타이머 시작
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateTimer(),
      );

      debugPrint('[MapScreen] 🏃 조깅 시작');

      // 위치 스트림 시작
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((Position position) {
            final latLng = NLatLng(position.latitude, position.longitude);

            // 실시간 계산
            if (_currentRoute.points.isNotEmpty) {
              final lastPoint = _currentRoute.points.last;
              final dist = Geolocator.distanceBetween(
                lastPoint.latitude,
                lastPoint.longitude,
                position.latitude,
                position.longitude,
              );
              _totalDistance += dist;

              final distKm = _totalDistance / 1000;
              _calories = (distKm * 70).toInt();
              _updatePace(distKm);
            }

            setState(() {
              _currentRoute.addPoint(latLng);
            });

            if (_mapController != null) {
              RoutePainter.drawRoute(_mapController!, _currentRoute);
            }
          });
    });
  }

  void _pauseExercise() {
    setState(() {
      _isPaused = true;
      _stopwatch.stop();
      _positionStreamSubscription?.pause();
    });
  }

  void _resumeExercise() {
    setState(() {
      _isPaused = false;
      _stopwatch.start();
      _positionStreamSubscription?.resume();
    });
  }

  void _stopExercise() {
    setState(() {
      _stopwatch.stop();
      _timer?.cancel();
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _currentRoute.stop();
    });
    _showSummaryDialog();
  }

  void _updateTimer() {
    if (_isRunning && !_isPaused) {
      setState(() {
        _elapsed = _stopwatch.elapsed;
      });
    }
  }

  void _updatePace(double distKm) {
    if (distKm > 0 && _elapsed.inSeconds > 0) {
      final secondsPerKm = _elapsed.inSeconds / distKm;
      final pMin = secondsPerKm ~/ 60;
      final pSec = (secondsPerKm % 60).toInt();
      _pace = "$pMin'${pSec.toString().padLeft(2, '0')}''";
    }
  }

  // ─────────────────────────────────────
  // 카메라를 내 위치로 이동
  // ─────────────────────────────────────
  Future<void> _moveToMyLocation() async {
    if (_mapController == null) return;
    _mapController!.setLocationTrackingMode(NLocationTrackingMode.follow);
  }

  // ─────────────────────────────────────
  // 조깅 종료 후 요약 팝업 표시
  // ─────────────────────────────────────
  void _showSummaryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🏃 오늘의 러닝 요약'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('총 주행 거리: ${(_totalDistance / 1000).toStringAsFixed(2)} km'),
            Text('소모 칼로리: $_calories kcal'),
            Text('평균 페이스: $_pace'),
            Text('총 운동 시간: ${_formatDuration(_elapsed)}'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reset();
            },
            child: const Text('기록 저장 및 닫기'),
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _totalDistance = 0.0;
      _calories = 0;
      _pace = "0'00''";
      _elapsed = Duration.zero;
      _stopwatch.reset();
      if (_mapController != null) {
        RoutePainter.clearRoute(_mapController!);
      }
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
          NaverMap(options: _mapOptions, onMapReady: _onMapReady),

          // 3. 하단 UI(대시보드) 구현
          Positioned(bottom: 40, left: 20, right: 20, child: _buildDashboard()),
        ],
      ),
    );
  }

  // ─────────────────────────────────────
  // 대시보드 위젯 빌더
  // ─────────────────────────────────────
  Widget _buildDashboard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9), // 반투명 하얀색
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoItem("시간", _formatDuration(_elapsed)),
          _buildInfoItem(
            "거리",
            "${(_totalDistance / 1000).toStringAsFixed(2)} km",
          ),
          _buildInfoItem("페이스", _pace),
          _buildInfoItem("칼로리", "$_calories kcal"),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
