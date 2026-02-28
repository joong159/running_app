import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/jog_route.dart';
import '../models/run_record.dart';
import '../services/run_history_service.dart';
import '../services/route_painter.dart';
import 'history_screen.dart';
import 'community_screen.dart';
import '../models/course.dart'; // Course 모델 import

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

  // 스크린샷 컨트롤러
  final _screenshotController = ScreenshotController();

  // 조깅 경로 모델 (Polyline 확장 포인트)
  JogRoute _currentRoute = JogRoute();

  // 📍 선택된 코스 경로 오버레이 (미리보기용)
  NPathOverlay? _selectedCourseOverlay;

  // 조깅 중 여부
  bool _isRunning = false;
  bool _isPaused = false;

  // 서비스 및 데이터 변수
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  Uint8List? _lastRunMapSnapshot;

  // 1. 데이터 변수 선언 (실시간 계산용)
  double _totalDistance = 0.0; // meters
  int _calories = 0; // kcal
  String _pace = "0'00''"; // min/km
  final Stopwatch _stopwatch = Stopwatch();
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  List<double> _kmSplits = []; // 📍 구간별 페이스 저장용 리스트
  Duration _lastSplitTime = Duration.zero; // 마지막 구간 측정 시간

  // 2. TTS 변수 선언
  late FlutterTts _flutterTts;
  int _lastKmAnnounced = 0;
  int _lastMinuteAnnounced = 0;
  DateTime? _lastSpeakTime; // 음성 안내 쿨타임 제어용

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

    // 1. 내 위치로 카메라 이동 및 추적 모드 설정
    await _moveToMyLocation();

    // 2. Firestore에서 주변 코스 불러오기 (플랫폼 확장성 핵심!)
    await _loadNearbyCourses();
  }

  /// 📍 Firestore에서 코스 정보를 가져와 지도에 마커로 표시
  Future<void> _loadNearbyCourses() async {
    if (_mapController == null) return;

    try {
      // 1. Firestore에서 코스 목록 가져오기
      final courses = await _firestoreService.getCourses();
      debugPrint('[MapScreen] 📍 불러온 코스 개수: ${courses.length}개');

      for (var course in courses) {
        // 2. 마커 생성
        final marker = NMarker(
          id: course.id,
          position: course.position,
          caption: NOverlayCaption(text: course.title),
          iconTintColor: Colors.indigoAccent, // 추천 코스는 남색으로 표시
        );

        // 3. 마커 클릭 리스너 (정보창 띄우기)
        marker.setOnTapListener((overlay) {
          _showCourseInfoDialog(course);
          _previewCoursePath(course); // 📍 경로 미리보기 그리기
        });

        // 4. 지도에 추가
        _mapController!.addOverlay(marker);
      }
    } catch (e) {
      debugPrint('[MapScreen] ❌ 코스 마커 로딩 실패: $e');
    }
  }

  /// 📍 선택한 코스의 경로를 지도에 그리기
  void _previewCoursePath(Course course) {
    if (_mapController == null) return;

    // 1. 기존에 그려진 경로가 있다면 제거
    if (_selectedCourseOverlay != null) {
      _mapController!.deleteOverlay(_selectedCourseOverlay!.info);
      _selectedCourseOverlay = null;
    }

    // 2. 경로 데이터가 없으면 리턴 (혹은 마커 위치에 원 그리기 등 대체 가능)
    if (course.path.isEmpty) return;

    // 3. 새로운 경로 오버레이 생성
    _selectedCourseOverlay = NPathOverlay(
      id: 'course_preview_${course.id}',
      coords: course.path,
      width: 10,
      color: Colors.indigoAccent.withOpacity(0.7), // 미리보기는 약간 투명하게
      outlineWidth: 2,
      outlineColor: Colors.white,
    );

    // 4. 지도에 추가
    _mapController!.addOverlay(_selectedCourseOverlay!);

    // 5. (선택 사항) 경로가 잘 보이도록 카메라 이동
    // final bounds = NLatLngBounds.from(course.path);
    // _mapController!.updateCamera(NCameraUpdate.fitBounds(bounds, padding: const EdgeInsets.all(40)));
  }

  /// 코스 상세 정보 바텀 시트
  void _showCourseInfoDialog(Course course) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag, color: Colors.indigo, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      course.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                course.description,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCourseStat(
                    Icons.straighten,
                    '${course.distanceKm}km',
                    '총 거리',
                  ),
                  _buildCourseStat(Icons.timer, '예상 30분', '소요 시간'), // 예상 시간은 임시
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: 해당 코스로 내비게이션 시작 기능 연결
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${course.title} 코스로 안내를 시작합니다!')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('이 코스로 달리기'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCourseStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
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

      // 📍 운동 시작 시 미리보기 경로 제거 (깔끔하게)
      if (_selectedCourseOverlay != null && _mapController != null) {
        _mapController!.deleteOverlay(_selectedCourseOverlay!.info);
        _selectedCourseOverlay = null;
      }

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
      _kmSplits = []; // 초기화
      _lastSplitTime = Duration.zero; // 초기화

      // 운동 시작 음성 안내
      _speak("가온길 러닝을 시작합니다.", force: true);

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

              // 1km 마다 음성 안내
              final currentKm = (_totalDistance / 1000).floor();
              if (currentKm > 0 && currentKm > _lastKmAnnounced) {
                // 📍 1km 구간 페이스 계산 및 저장
                final nowElapsed = _stopwatch.elapsed;
                final durationSinceLast = nowElapsed - _lastSplitTime;
                final splitMinutes =
                    durationSinceLast.inSeconds / 60.0; // 분 단위 변환
                _kmSplits.add(splitMinutes);
                _lastSplitTime = nowElapsed;

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

  void _stopExercise() async {
    _stopwatch.stop();
    _timer?.cancel();
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _currentRoute.stop();

    // 운동 종료 음성 안내
    final totalKm = (_totalDistance / 1000).toStringAsFixed(2);
    await _speak("운동을 종료합니다. 오늘 총 ${totalKm}km를 달렸습니다. 수고하셨습니다.", force: true);

    // 지도 스냅샷 캡처
    final snapshotFile = await _mapController?.takeSnapshot(
      showControls: false,
    );
    if (snapshotFile != null) {
      _lastRunMapSnapshot = await snapshotFile.readAsBytes();
    }

    setState(() {
      _isRunning = false;
      _isPaused = false;
    });

    // 요약 다이얼로그 표시
    if (mounted) {
      _showSummaryDialog();
    }
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
  Future<void> _speak(String text, {bool force = false}) async {
    // 운동 중이 아니면 안내하지 않음 (단, 강제 안내는 예외 - 예: 운동 종료 시)
    if (!_isRunning && !force) return;

    final now = DateTime.now();
    // 강제 안내가 아니고, 마지막 안내로부터 10초가 지나지 않았으면 무시 (중복 안내 방지)
    if (!force && _lastSpeakTime != null) {
      if (now.difference(_lastSpeakTime!) < const Duration(seconds: 10)) {
        return;
      }
    }

    await _flutterTts.speak(text);
    _lastSpeakTime = now;
  }

  void _announceStatus({required bool isKmAnnounce}) {
    if (isKmAnnounce) {
      // 페이스 포맷 변환 (예: 5'30'' -> 5분 30초) - TTS가 더 자연스럽게 읽도록 처리
      final ttsPace = _pace.replaceAll("'", "분 ").replaceAll("''", "초");
      String announcement =
          "현재 $_lastKmAnnounced 킬로미터 주행 완료. 페이스는 $ttsPace입니다.";
      _speak(announcement, force: true);
    } else {
      final distKm = (_totalDistance / 1000).toStringAsFixed(2);
      final time = _formatDuration(_elapsed);
      String announcement =
          "현재까지 $distKm 킬로미터를, $time 동안 달렸습니다. 현재 페이스는 $_pace 입니다.";
      _speak(announcement, force: true);
    }
  }

  // ─────────────────────────────────────
  // 카메라를 내 위치로 이동
  // ─────────────────────────────────────
  Future<void> _moveToMyLocation() async {
    if (_mapController == null) return;

    // 현재 위치 가져오기 (Geolocator)
    final position = await Geolocator.getCurrentPosition();
    final latLng = NLatLng(position.latitude, position.longitude);

    // 카메라 이동 및 추적 모드 설정
    final cameraUpdate = NCameraUpdate.withParams(target: latLng, zoom: 15);
    await _mapController!.updateCamera(cameraUpdate);
    _mapController!.setLocationTrackingMode(NLocationTrackingMode.follow);
  }

  // ─────────────────────────────────────
  // 조깅 종료 후 요약 팝업 표시
  // ─────────────────────────────────────
  Future<void> _shareRun() async {
    // 로딩 인디케이터 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      if (_lastRunMapSnapshot == null) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지도 스크린샷 생성에 실패했습니다.')));
        return;
      }

      // 2. 공유 카드 위젯 생성
      final shareCard = _ShareCard(
        mapImage: _lastRunMapSnapshot!,
        distance: (_totalDistance / 1000).toStringAsFixed(2),
        time: _formatDuration(_elapsed),
        pace: _pace,
        calories: _calories,
      );

      // 3. 위젯을 이미지로 캡처 (screenshot 라이브러리 활용)
      final imageBytes = await _screenshotController.captureFromWidget(
        Material(child: shareCard),
        pixelRatio: 2.0, // 고해상도 이미지 생성
        targetSize: const Size(540, 960), // 9:16 비율
      );

      // 4. 임시 파일로 저장 (path_provider 활용)
      final tempDir = await getTemporaryDirectory();
      final imagePath = '${tempDir.path}/gaongil_run.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageBytes);

      Navigator.pop(context); // 로딩 닫기

      // 5. 공유 시트 띄우기 (share_plus 활용)
      await Share.shareXFiles([
        XFile(imagePath),
      ], text: '오늘도 달렸다! #가온길 #러닝 #오운완');
    } catch (e) {
      Navigator.pop(context); // 로딩 닫기
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('공유 이미지 생성 중 오류 발생: $e')));
    }
  }

  void _showSummaryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 외부 탭으로 닫기 방지
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.directions_run, color: Colors.green),
            SizedBox(width: 8),
            Text('오늘의 러닝 요약'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "총 ${(_totalDistance / 1000).toStringAsFixed(2)}km를 주행하셨습니다.",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildSummaryItem(
              Icons.route_outlined,
              '${(_totalDistance / 1000).toStringAsFixed(2)} km',
              '총 거리',
            ),
            const SizedBox(height: 12),
            _buildSummaryItem(
              Icons.timer_outlined,
              _formatDuration(_elapsed),
              '운동 시간',
            ),
            const SizedBox(height: 12),
            _buildSummaryItem(Icons.speed_outlined, _pace, '평균 페이스'),
            const SizedBox(height: 12),
            _buildSummaryItem(
              Icons.local_fire_department_outlined,
              '$_calories kcal',
              '소모 칼로리',
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    try {
                      // 1. 로컬에 저장
                      final record = RunRecord(
                        date: DateTime.now(),
                        totalDistanceKm: _totalDistance / 1000,
                        duration: _elapsed,
                        calories: _calories,
                        pace: _pace,
                        paceSegments: _kmSplits, // 📍 저장 시 구간 기록 포함
                        routePath: _currentRoute.points, // 📍 이동 경로 저장
                      );
                      await RunHistoryService().saveRun(record);

                      // 2. Firebase에 업로드
                      if (_authService.currentUser != null &&
                          _lastRunMapSnapshot != null) {
                        await _firestoreService.uploadRunRecord(
                          record,
                          _authService.currentUser!,
                          _lastRunMapSnapshot!,
                        );
                      }
                    } catch (e) {
                      debugPrint('저장/업로드 중 오류 발생 (무시하고 닫기): $e');
                    }

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _reset();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('운동 기록이 성공적으로 저장되었습니다.')),
                    );
                  },
                  child: const Text('저장하고 닫기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareRun,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('공유 이미지 만들기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE1306C), // 인스타 색상
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const Spacer(),
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
      _totalDistance = 0.0;
      _calories = 0;
      _pace = "0'00''";
      _elapsed = Duration.zero;
      _stopwatch.reset();
      if (_mapController != null) {
        RoutePainter.clearRoute(_mapController!);
      }
      _lastRunMapSnapshot = null;
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
            icon: const Icon(Icons.people),
            tooltip: '커뮤니티 피드',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommunityScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '기록 보기',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: '내 위치로 이동',
            onPressed: _moveToMyLocation,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── 네이버 지도 ──
          NaverMap(options: _mapOptions, onMapReady: _onMapReady),

          // 랭킹 대시보드
          Positioned(
            bottom: 220,
            left: 20,
            right: 20,
            child: _buildRankingDashboard(),
          ),

          // 주간 통계 대시보드 (좌측 상단)
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: _buildWeeklyStatsCard(),
          ),

          // 운동 정보 대시보드
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: _buildRunDashboard(),
          ),

          // 운동 시작/종료 버튼
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
  Widget _buildRunDashboard() {
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
          Expanded(child: _buildInfoItem("시간", _formatDuration(_elapsed))),
          Expanded(
            child: _buildInfoItem(
              "거리",
              "${(_totalDistance / 1000).toStringAsFixed(2)} km",
            ),
          ),
          Expanded(child: _buildInfoItem("페이스", _pace)),
          Expanded(child: _buildInfoItem("칼로리", "$_calories kcal")),
        ],
      ),
    );
  }

  /// 랭킹 정보 대시보드
  Widget _buildRankingDashboard() {
    final user = _authService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>>(
      future: _firestoreService.getRankingData(user),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink(); // 데이터 없으면 표시 안함
        }
        final rankingData = snapshot.data!;
        final percentile = (rankingData['percentile'] as double? ?? 0.0) * 100;
        final group = rankingData['group'] as String? ?? '그룹';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.military_tech, color: Colors.amber, size: 24),
              const SizedBox(width: 12),
              Text(
                '$group 내 상위 ${percentile.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '입니다!',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 주간 통계 카드 (이번 주 vs 지난 주)
  Widget _buildWeeklyStatsCard() {
    final user = _authService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, double>>(
      future: _firestoreService.getWeeklyStats(user.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final thisWeek = snapshot.data!['thisWeek']!;
        final lastWeek = snapshot.data!['lastWeek']!;
        final diff = thisWeek - lastWeek;
        final isPositive = diff >= 0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.trending_up, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                '이번 주 ${thisWeek.toStringAsFixed(1)}km',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${isPositive ? '+' : ''}${diff.toStringAsFixed(1)}km)',
                style: TextStyle(
                  color: isPositive ? Colors.red : Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// ─────────────────────────────────────
// 인스타그램 공유 카드 위젯
// ─────────────────────────────────────
class _ShareCard extends StatelessWidget {
  final Uint8List mapImage;
  final String distance; // km string without unit
  final String time;
  final String pace;
  final int calories;

  const _ShareCard({
    required this.mapImage,
    required this.distance,
    required this.time,
    required this.pace,
    required this.calories,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 배경: 지도 캡처
          Image.memory(mapImage, fit: BoxFit.cover),

          // 2. 어두운 그라데이션 오버레이
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.4, 0.6, 1.0],
              ),
            ),
          ),

          // 3. 중앙 로고
          const Center(
            child: Text(
              '가온길',
              style: TextStyle(
                color: Colors.white,
                fontSize: 80,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                shadows: [Shadow(blurRadius: 10.0, color: Colors.black54)],
              ),
            ),
          ),

          // 4. 하단 정보
          Positioned(
            bottom: 40,
            left: 32,
            right: 32,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatItem('거리', distance, 'km'),
                    _buildStatItem('시간', time, ''),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatItem('페이스', pace, ''),
                    _buildStatItem('칼로리', '$calories', 'kcal'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (unit.isNotEmpty) const SizedBox(width: 4),
            if (unit.isNotEmpty)
              Text(
                unit,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
