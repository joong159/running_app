import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 네이버 지도 초기화 (아이디 한 번 더 입력!)
  await NaverMapSdk.instance.initialize(
    clientId: 'fk2ymrgrxq', // 네이버 지도 API 키
    onAuthFailed: (ex) => print("네이버 지도 인증 실패: $ex"),
  );

  runApp(const JoggingApp());
}

class JoggingApp extends StatelessWidget {
  const JoggingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('현중님의 조깅 코스 추천'),
          backgroundColor: Colors.green,
        ),
        body: const NaverMap(
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: NLatLng(37.5666, 126.9784), // 서울 시청 기준
              zoom: 15,
            ),
          ),
        ),
      ),
    );
  }
}
