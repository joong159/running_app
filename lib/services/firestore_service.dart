import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:running_app/models/run_record.dart';
import 'package:running_app/models/course.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 운동 기록 및 지도 이미지를 Firebase에 업로드
  Future<void> uploadRunRecord(
    RunRecord record,
    User user,
    Uint8List mapImage,
  ) async {
    try {
      // 1. 사용자 프로필 가져오기
      final userRef = _db.collection('users').doc(user.uid);
      final userProfile = await userRef.get();
      if (!userProfile.exists) {
        throw Exception('사용자 프로필이 존재하지 않습니다.');
      }
      final userData = userProfile.data()!;

      // 2. 이미지를 Firebase Storage에 업로드
      final imageRef = _storage.ref(
        'run_maps/${user.uid}/${record.date.toIso8601String()}.png',
      );
      await imageRef.putData(mapImage);
      final imageUrl = await imageRef.getDownloadURL();

      // 3. Firestore에 기록 저장 (개별 러닝 로그)
      await _db.collection('runs').add({
        'userId': user.uid,
        'userName': userData['name'],
        'userAgeGroup': userData['ageGroup'],
        'userGender': userData['gender'],
        'distanceKm': record.totalDistanceKm,
        'durationSeconds': record.duration.inSeconds,
        'pace': record.pace,
        'calories': record.calories,
        'timestamp': record.date,
        'mapImageUrl': imageUrl,
        'likes': 0,
        'paceSegments': record.paceSegments, // 📍 구간 기록 저장
        'routePath': record.routePath
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(), // 📍 경로 데이터 저장
      });

      // 4. 사용자 누적 통계 업데이트 (랭킹/대시보드용 데이터 수집)
      // FieldValue.increment를 사용하여 동시성 문제 없이 안전하게 합산합니다.
      await userRef.update({
        'totalDistance': FieldValue.increment(record.totalDistanceKm),
        'totalTime': FieldValue.increment(record.duration.inSeconds),
        'totalRuns': FieldValue.increment(1),
        'lastRunAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreService] ❌ 기록 업로드 실패: $e');
      rethrow;
    }
  }

  /// 커뮤니티 피드 데이터 스트림
  Stream<QuerySnapshot> getCommunityFeed() {
    return _db
        .collection('runs')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// 랭킹 데이터 계산
  Future<Map<String, dynamic>> getRankingData(User user) async {
    try {
      final userProfile = await _db.collection('users').doc(user.uid).get();
      if (!userProfile.exists) return {};

      final userData = userProfile.data()!;
      final ageGroup = userData['ageGroup'];
      final gender = userData['gender'];
      final myBestDistance = await _getMyBestDistance(user.uid);

      final groupRuns = await _db
          .collection('runs')
          .where('userAgeGroup', isEqualTo: ageGroup)
          .where('userGender', isEqualTo: gender)
          .get();

      if (groupRuns.docs.isEmpty)
        return {'percentile': 1.0, 'group': '$ageGroup대 $gender'};

      final betterRuns = groupRuns.docs
          .where((doc) => doc['distanceKm'] > myBestDistance)
          .length;

      final percentile = 1.0 - (betterRuns / groupRuns.docs.length);

      return {'percentile': percentile, 'group': '$ageGroup대 $gender'};
    } catch (e) {
      debugPrint('[FirestoreService] ❌ 랭킹 데이터 계산 실패: $e');
      return {};
    }
  }

  Future<double> _getMyBestDistance(String uid) async {
    final myRuns = await _db
        .collection('runs')
        .where('userId', isEqualTo: uid)
        .orderBy('distanceKm', descending: true)
        .limit(1)
        .get();
    if (myRuns.docs.isEmpty) return 0.0;
    return myRuns.docs.first['distanceKm'];
  }

  /// 📍 추천 코스 데이터 가져오기
  /// (MVP 단계에서는 모든 코스를 가져오지만, 추후 GeoHash 등을 이용해 반경 검색으로 고도화 가능)
  Future<List<Course>> getCourses() async {
    try {
      final snapshot = await _db.collection('courses').get();
      return snapshot.docs.map((doc) {
        return Course.fromMap(doc.id, doc.data());
      }).toList();
    } catch (e) {
      debugPrint('[FirestoreService] ❌ 코스 데이터 로딩 실패: $e');
      return [];
    }
  }

  /// 📜 특정 사용자의 러닝 기록 가져오기 (HistoryScreen용)
  Future<List<RunRecord>> getUserRuns(String uid) async {
    try {
      final snapshot = await _db
          .collection('runs')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return RunRecord(
          id: doc.id, // 📍 문서 ID 매핑
          date: (data['timestamp'] as Timestamp).toDate(),
          totalDistanceKm: (data['distanceKm'] as num).toDouble(),
          duration: Duration(seconds: data['durationSeconds'] as int),
          calories: data['calories'] as int,
          pace: data['pace'] as String,
          paceSegments:
              (data['paceSegments'] as List<dynamic>?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              [],
          routePath:
              (data['routePath'] as List<dynamic>?)
                  ?.map(
                    (e) => NLatLng(
                      (e['lat'] as num).toDouble(),
                      (e['lng'] as num).toDouble(),
                    ),
                  )
                  .toList() ??
              [],
        );
      }).toList();
    } catch (e) {
      debugPrint('[FirestoreService] ❌ 기록 로딩 실패: $e');
      return [];
    }
  }

  /// 🗑️ 러닝 기록 삭제
  Future<void> deleteRun(String runId, String userId, RunRecord record) async {
    try {
      // 1. 러닝 기록 문서 삭제
      await _db.collection('runs').doc(runId).delete();

      // 2. 사용자 누적 통계 차감 (선택 사항: 기록 삭제 시 통계도 되돌리기)
      await _db.collection('users').doc(userId).update({
        'totalDistance': FieldValue.increment(-record.totalDistanceKm),
        'totalTime': FieldValue.increment(-record.duration.inSeconds),
        'totalRuns': FieldValue.increment(-1),
      });
    } catch (e) {
      debugPrint('[FirestoreService] ❌ 기록 삭제 실패: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────
  // ❤️ 소셜 기능 (좋아요)
  // ─────────────────────────────────────
  Future<void> toggleLike(String runId, String userId) async {
    final runRef = _db.collection('runs').doc(runId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(runRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final List<dynamic> likedBy = List.from(data['likedBy'] ?? []);
      int likes = data['likes'] ?? 0;

      if (likedBy.contains(userId)) {
        likedBy.remove(userId);
        likes = (likes > 0) ? likes - 1 : 0;
      } else {
        likedBy.add(userId);
        likes += 1;
      }

      transaction.update(runRef, {'likes': likes, 'likedBy': likedBy});
    });
  }

  // ─────────────────────────────────────
  // 📊 데이터 시각화 (주간 통계)
  // ─────────────────────────────────────
  Future<Map<String, double>> getWeeklyStats(String userId) async {
    final now = DateTime.now();
    // 이번 주 월요일 계산
    final startOfThisWeek = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));

    try {
      final snapshot = await _db
          .collection('runs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfLastWeek)
          .get();

      double thisWeek = 0.0;
      double lastWeek = 0.0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final date = (data['timestamp'] as Timestamp).toDate();
        final dist = (data['distanceKm'] as num).toDouble();

        if (date.isBefore(startOfThisWeek)) {
          lastWeek += dist;
        } else {
          thisWeek += dist;
        }
      }
      return {'thisWeek': thisWeek, 'lastWeek': lastWeek};
    } catch (e) {
      debugPrint('❌ 주간 통계 오류: $e');
      return {'thisWeek': 0.0, 'lastWeek': 0.0};
    }
  }

  // ─────────────────────────────────────
  // 🏃 크루(Crew) 기능
  // ─────────────────────────────────────
  Stream<QuerySnapshot> getCrews() {
    return _db
        .collection('crews')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> createCrew(
    String name,
    String description,
    int maxMembers,
    User user,
  ) async {
    await _db.collection('crews').add({
      'name': name,
      'description': description,
      'maxMembers': maxMembers,
      'currentMembers': 1,
      'members': [user.uid],
      'leaderId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
