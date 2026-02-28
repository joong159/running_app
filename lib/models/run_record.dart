import 'dart:convert';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class RunRecord {
  final String? id; // 📍 Firestore 문서 ID (삭제 시 필요)
  final DateTime date;
  final double totalDistanceKm;
  final Duration duration;
  final int calories;
  final String pace;
  final List<double> paceSegments; // 📍 1km 구간별 페이스 (분/km)
  final List<NLatLng> routePath; // 📍 이동 경로 좌표 리스트

  RunRecord({
    this.id,
    required this.date,
    required this.totalDistanceKm,
    required this.duration,
    required this.calories,
    required this.pace,
    this.paceSegments = const [],
    this.routePath = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'totalDistanceKm': totalDistanceKm,
      'duration': duration.inSeconds,
      'calories': calories,
      'pace': pace,
      'paceSegments': paceSegments,
      'routePath': routePath
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
    };
  }

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      id: json['id'] as String?,
      date: DateTime.parse(json['date']),
      totalDistanceKm: (json['totalDistanceKm'] as num).toDouble(),
      duration: Duration(seconds: json['duration']),
      calories: json['calories'],
      pace: json['pace'],
      paceSegments:
          (json['paceSegments'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      routePath:
          (json['routePath'] as List<dynamic>?)
              ?.map(
                (e) => NLatLng(
                  (e['lat'] as num).toDouble(),
                  (e['lng'] as num).toDouble(),
                ),
              )
              .toList() ??
          [],
    );
  }
}
