import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// 사용자 인증 상태 변경을 감지하는 스트림
  Stream<User?> get userStream => _auth.authStateChanges();

  /// 현재 로그인된 사용자 객체
  User? get currentUser => _auth.currentUser;

  /// 구글 계정으로 로그인
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // 사용자가 창을 닫은 경우

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      return userCredential.user;
    } catch (e) {
      debugPrint('[AuthService] ❌ 구글 로그인 실패: $e');
      return null;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Firestore에 사용자 프로필이 존재하는지 확인
  Future<bool> isNewUser(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    return !doc.exists;
  }

  /// 사용자 프로필 생성 (최초 1회)
  Future<void> createUserProfile({
    required User user,
    required String name,
    required int age,
    required String gender,
    required String region,
  }) async {
    // 나이대를 계산 (예: 27세 -> 20대)
    final ageGroup = (age ~/ 10) * 10;

    final userProfile = {
      'uid': user.uid,
      'email': user.email,
      'name': name,
      'age': age,
      'ageGroup': ageGroup,
      'gender': gender,
      'region': region,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(user.uid).set(userProfile);
  }

  /// 현재 사용자의 프로필 정보 가져오기
  Future<DocumentSnapshot?> getUserProfile() async {
    if (currentUser == null) return null;
    try {
      final doc = await _db.collection('users').doc(currentUser!.uid).get();
      if (doc.exists) {
        return doc;
      }
    } catch (e) {
      debugPrint('[AuthService] ❌ 프로필 로딩 실패: $e');
    }
    return null;
  }
}
