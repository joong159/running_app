import 'dart:math' as math;
import 'package:flutter_naver_map/flutter_naver_map.dart';

// ─────────────────────────────────────────────
// JogRoute
// 조깅 경로 데이터를 관리하는 모델 클래스.
// GPS 좌표 포인트 목록, 거리 계산, 시간 측정을 담당합니다.
//
// [확장 방법]
//   1. GPS 스트림 구독 시 addPoint(latLng) 호출
//   2. RoutePainter.drawRoute(controller, this) 로 지도에 경로 표시
// ─────────────────────────────────────────────
class JogRoute {
  final List<NLatLng> points = [];
  DateTime? _startTime;
  DateTime? _endTime;

  bool get isRunning => _startTime != null && _endTime == null;

  /// 조깅 시작
  void start() {
    points.clear();
    _startTime = DateTime.now();
    _endTime = null;
  }

  /// 조깅 종료
  void stop() {
    _endTime = DateTime.now();
  }

  /// GPS 좌표 추가
  void addPoint(NLatLng latLng) {
    points.add(latLng);
  }

  // ─────────────────────────────────────
  // 총 거리 계산 (Haversine 공식, 단위: km)
  // ─────────────────────────────────────
  double get totalDistanceKm {
    if (points.length < 2) return 0.0;

    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _haversineKm(points[i], points[i + 1]);
    }
    return total;
  }

  static double _haversineKm(NLatLng a, NLatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);

    final h =
        sinDLat * sinDLat +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            sinDLon *
            sinDLon;

    return 2 * earthRadiusKm * math.asin(math.sqrt(h));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  // ─────────────────────────────────────
  // 경과 시간 (mm:ss 포맷)
  // ─────────────────────────────────────
  String get elapsedTimeFormatted {
    if (_startTime == null) return '00:00';
    final end = _endTime ?? DateTime.now();
    final elapsed = end.difference(_startTime!);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration get elapsedDuration {
    if (_startTime == null) return Duration.zero;
    final end = _endTime ?? DateTime.now();
    return end.difference(_startTime!);
  }
}
