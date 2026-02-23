import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../models/jog_route.dart';

class RoutePainter {
  /// 지도에 경로(PathOverlay)를 그립니다.
  static void drawRoute(NaverMapController controller, JogRoute route) {
    // 경로를 그리려면 최소 2개의 좌표가 필요합니다.
    if (route.points.length < 2) return;

    // NPathOverlay 생성
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
}
