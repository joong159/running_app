import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  // 2. TTS 변수 선언
  late FlutterTts _flutterTts;
  int _lastKmAnnounced = 0;
  int _lastMinuteAnnounced = 0;

  // 3. 고급 내비게이션 변수 선언
  // 예시 추천 경로 (대진대학교 주변)
  static final List<NLatLng> _recommendedRoutePoints = [
    const NLatLng(37.8747, 127.1552), // 대진대 운동장
    const NLatLng(37.8755, 127.1565),
    const NLatLng(37.8760, 127.1558),
    const NLatLng(37.8752, 127.1545),
    const NLatLng(37.8747, 127.1552),
  ];
  int _nextWaypointIndex = 0;
  bool _isOffRoute = false;
  bool _isApproachingWaypoint = false;

  // 위치 스트림 구독 (조깅 중일 때만 활성화)
  StreamSubscription<Position>? _positionStreamSubscription;

  // 서울 시청 초기 좌표
  static const NLatLng _seoulCityHall = NLatLng(37.5666, 126.9784);

  @override
  void initState() {
    super.initState();
    _initTts();
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

  /// TTS 초기화
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    debugPrint('[TTS] ✅ TTS 초기화 완료');
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

    // 4. 추천 경로 그리기
    final recommendedPathOverlay = NPathOverlay(
      id: 'recommended_path',
      coords: _recommendedRoutePoints,
      width: 8,
      color: Colors.blue.withOpacity(0.6),
      outlineWidth: 2,
      outlineColor: Colors.blueAccent,
    );
    controller.addOverlay(recommendedPathOverlay);
    debugPrint('[MapScreen] ✅ 추천 경로 표시 완료');
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
    _flutterTts.stop();
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
      _lastKmAnnounced = 0;
      _lastMinuteAnnounced = 0;
      _nextWaypointIndex = 0;
      _isOffRoute = false;
      _isApproachingWaypoint = false;

      // 운동 시작 음성 안내
      _speak("가온길 러닝을 시작합니다. 즐거운 운동 되세요!");

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

            // 내비게이션 로직 처리 (경로 이탈, 방향 전환)
            _checkNavigationCues(latLng);

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

              // 1km 마다 음성 안내
              final currentKm = (_totalDistance / 1000).floor();
              if (currentKm > 0 && currentKm > _lastKmAnnounced) {
                _lastKmAnnounced = currentKm;
                _announceStatus(isKmAnnounce: true);
              }
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

      // 운동 종료 음성 안내
      final totalKm = (_totalDistance / 1000).toStringAsFixed(2);
      _speak("오늘의 운동을 종료합니다. 총 ${totalKm}킬로미터를 주행하셨습니다.");
    });
    _showSummaryDialog();
  }

  void _updateTimer() {
    if (_isRunning && !_isPaused) {
      setState(() {
        _elapsed = _stopwatch.elapsed;

        // 5분 마다 음성 안내
        final currentMinute = _elapsed.inMinutes;
        if (currentMinute > 0 &&
            currentMinute % 5 == 0 &&
            currentMinute != _lastMinuteAnnounced) {
          _lastMinuteAnnounced = currentMinute;
          _announceStatus(isKmAnnounce: false);
        }
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
  // TTS 음성 안내
  // ─────────────────────────────────────
  Future<void> _speak(String text) async {
    // isRunning 상태일 때만 말하도록 하여, 종료 후의 불필요한 안내를 막습니다.
    if (_isRunning) {
      await _flutterTts.speak(text);
    }
  }

  void _announceStatus({required bool isKmAnnounce}) {
    if (isKmAnnounce) {
      final kcal = _calories;
      String announcement =
          "현재 $_lastKmAnnounced 킬로미터 주행 완료. 페이스는 $_pace, 소모 칼로리는 $kcal 칼로리입니다.";
      _speak(announcement);
    } else {
      final distKm = (_totalDistance / 1000).toStringAsFixed(2);
      final time = _formatDuration(_elapsed);
      String announcement =
          "현재까지 $distKm 킬로미터를, $time 동안 달렸습니다. 현재 페이스는 $_pace 입니다.";
      _speak(announcement);
    }
  }

  // ─────────────────────────────────────
  // 고급 내비게이션 로직
  // ─────────────────────────────────────
  void _checkNavigationCues(NLatLng currentLatLng) {
    if (_recommendedRoutePoints.length < 2) return;

    // 1. 경로 이탈 감지
    final minDistanceToRoute = _distanceToPolyline(
      currentLatLng,
      _recommendedRoutePoints,
    );
    if (minDistanceToRoute > 10.0 && !_isOffRoute) {
      _speak("경로를 벗어났습니다. 원래 코스로 복귀하세요.");
      setState(() => _isOffRoute = true);
    } else if (minDistanceToRoute <= 10.0 && _isOffRoute) {
      setState(() => _isOffRoute = false);
    }

    // 2. 회전 지점 안내
    if (_nextWaypointIndex < _recommendedRoutePoints.length) {
      final nextWaypoint = _recommendedRoutePoints[_nextWaypointIndex];
      final distanceToWaypoint = Geolocator.distanceBetween(
        currentLatLng.latitude,
        currentLatLng.longitude,
        nextWaypoint.latitude,
        nextWaypoint.longitude,
      );

      // 50m 이내 접근 시 안내
      if (distanceToWaypoint < 50 && !_isApproachingWaypoint) {
        _speak("잠시 후 방향 전환 구간입니다.");
        setState(() => _isApproachingWaypoint = true);
      }

      // 15m 이내 통과 시 다음 웨이포인트로 업데이트
      if (distanceToWaypoint < 15) {
        setState(() {
          _nextWaypointIndex++;
          _isApproachingWaypoint = false; // 다음 웨이포인트 안내를 위해 초기화
        });
      }
    }
  }

  /// 한 점에서 폴리라인까지의 최단 거리를 계산합니다 (단위: meters).
  double _distanceToPolyline(NLatLng point, List<NLatLng> polyline) {
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final segmentStart = polyline[i];
      final segmentEnd = polyline[i + 1];

      final distanceToSegment = _distanceToSegment(
        point,
        segmentStart,
        segmentEnd,
      );
      if (distanceToSegment < minDistance) {
        minDistance = distanceToSegment;
      }
    }
    return minDistance;
  }

  /// 한 점에서 선분까지의 최단 거리를 계산합니다.
  double _distanceToSegment(NLatLng p, NLatLng a, NLatLng b) {
    final double pa = Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      a.latitude,
      a.longitude,
    );
    final double pb = Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      b.latitude,
      b.longitude,
    );
    final double ab = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );

    if (ab == 0) return pa;

    // 점 P가 선분 AB의 'A'쪽 외부에 있는 경우
    if (pow(pb, 2) > pow(pa, 2) + pow(ab, 2)) return pa;
    // 점 P가 선분 AB의 'B'쪽 외부에 있는 경우
    if (pow(pa, 2) > pow(pb, 2) + pow(ab, 2)) return pb;

    // 헤론의 공식을 사용하여 삼각형의 면적을 구하고, 이를 통해 높이(거리)를 계산
    final double s = (pa + pb + ab) / 2;
    final double area = sqrt(s * (s - pa) * (s - pb) * (s - ab));
    return (2 * area) / ab;
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
        title: const Text('🏃‍♂️ 오늘의 러닝 요약'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "총 ${(_totalDistance / 1000).toStringAsFixed(2)}km를 주행하셨습니다.",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildSummaryItem(
              '총 주행 거리',
              '${(_totalDistance / 1000).toStringAsFixed(2)} km',
            ),
            _buildSummaryItem('총 운동 시간', _formatDuration(_elapsed)),
            _buildSummaryItem('평균 페이스', _pace),
            _buildSummaryItem('소모 칼로리', '$_calories kcal'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reset();
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
      _nextWaypointIndex = 0;
      _isOffRoute = false;
      _isApproachingWaypoint = false;
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

          // 운동 시작/종료 버튼
          // 하단 대시보드(bottom: 40)와 겹치지 않도록 bottom: 140으로 조정
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.center,
              child: ElevatedButton(
                onPressed: _isRunning ? _stopExercise : _startExercise,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning ? Colors.redAccent : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 15,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _isRunning ? '운동 종료' : '운동 시작',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
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
