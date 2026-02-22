import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../models/jog_route.dart';

// ─────────────────────────────────────────────
// RoutePainter
// 지도 위에 조깅 경로(Polyline)를 그리는 서비스 클래스.
//
// [사용 방법]
//   조깅 중 GPS 포인트가 쌓이면:
//     await RoutePainter.drawRoute(controller, jogRoute);
//
//   경로를 지우려면:
//     await RoutePainter.clearRoute(controller);
// ─────────────────────────────────────────────
class RoutePainter {
  RoutePainter._();

  static const String _overlayId = 'jog_route_polyline';

  /// 경로를 지도에 그립니다.
  /// points가 2개 미만이면 그리지 않습니다.
  static Future<void> drawRoute(
    NaverMapController controller,
    JogRoute route, {
    Color lineColor = Colors.blue,
    double lineWidth = 5.0,
  }) async {
    if (route.points.length < 2) return;

    // 기존 Polyline 제거 후 새로 그리기
    await clearRoute(controller);

    final polyline = NPolylineOverlay(
      id: _overlayId,
      coords: route.points,
      color: lineColor,
      width: lineWidth,
    );

    await controller.addOverlay(polyline);
    debugPrint('[RoutePainter] 경로 그리기 완료. 포인트 수: ${route.points.length}');
  }

  /// 지도에서 경로 Polyline을 제거합니다.
  static Future<void> clearRoute(NaverMapController controller) async {
    await controller.clearOverlays(type: NOverlayType.polylineOverlay);
    debugPrint('[RoutePainter] 경로 제거 완료');
  }
}
