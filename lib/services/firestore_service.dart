import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:running_app/models/run_record.dart';

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
      final userProfile = await _db.collection('users').doc(user.uid).get();
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

      // 3. Firestore에 기록 저장
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
}
