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

  /// 경로를 지도에 그립니다.
  /// points가 2개 미만이면 그리지 않습니다.
  static void drawRoute(NaverMapController controller, JogRoute route) {
    if (route.points.length < 2) return;

    // NPathOverlay 생성 (경로선)
    // id가 같으면 기존 오버레이를 자동으로 갱신(업데이트)합니다.
    final pathOverlay = NPathOverlay(
      id: 'jogging_path',
      coords: route.points,
      width: 10, // 경로 두께
      color: Colors.green, // 경로 색상
      outlineWidth: 2, // 테두리 두께
      outlineColor: Colors.white, // 테두리 색상
    );

    // 지도에 추가
    controller.addOverlay(pathOverlay);
  }

  /// 지도에서 경로 Polyline을 제거합니다.
  static void clearRoute(NaverMapController controller) {
    controller.deleteOverlay(
      const NOverlayInfo(type: NOverlayType.pathOverlay, id: 'jogging_path'),
    );
  }
}
