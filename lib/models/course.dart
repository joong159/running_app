import 'package:flutter_naver_map/flutter_naver_map.dart';

class Course {
  final String id;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final List<NLatLng> path; // 📍 경로 데이터 필드

  Course({
    required this.id,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.path,
  });

  // 네이버 지도 좌표 객체로 변환
  NLatLng get position => NLatLng(latitude, longitude);

  factory Course.fromMap(String id, Map<String, dynamic> map) {
    // 📍 경로 데이터 파싱 로직
    List<NLatLng> parsedPath = [];
    if (map['path'] != null) {
      for (var point in map['path']) {
        if (point is Map) {
          parsedPath.add(
            NLatLng(
              ((point['lat'] ?? point['latitude'] ?? 0) as num).toDouble(),
              ((point['lng'] ?? point['longitude'] ?? 0) as num).toDouble(),
            ),
          );
        }
      }
    }

    return Course(
      id: id,
      title: map['title'] ?? '이름 없는 코스',
      description: map['description'] ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      distanceKm: (map['distanceKm'] as num).toDouble(),
      path: parsedPath,
    );
  }
}
