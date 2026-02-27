// lib/models/run_record.dart
import 'dart:convert';

class RunRecord {
  final DateTime date;
  final double totalDistanceKm;
  final Duration duration;
  final int calories;
  final String pace;
  // I can also add the route points if I want to redraw the route later.
  // final List<Map<String, double>> routePoints;

  RunRecord({
    required this.date,
    required this.totalDistanceKm,
    required this.duration,
    required this.calories,
    required this.pace,
    // required this.routePoints,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'totalDistanceKm': totalDistanceKm,
      'duration': duration.inSeconds,
      'calories': calories,
      'pace': pace,
    };
  }

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      date: DateTime.parse(json['date']),
      totalDistanceKm: json['totalDistanceKm'],
      duration: Duration(seconds: json['duration']),
      calories: json['calories'],
      pace: json['pace'],
    );
  }
}
