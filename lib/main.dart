import 'package:flutter/foundation.dart'; // debugPrint를 위해 필요해요
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 최신 방식의 초기화 (경고가 사라집니다)
  await NaverMapSdk.instance.initialize(
    clientId: 'fk2ymrgrxq',
    onAuthFailed: (ex) {
      debugPrint("네이버 지도 인증 실패: $ex");
    },
  );

  runApp(const JoggingApp()); // 이름을 JoggingApp으로 통일!
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
        body: NaverMap(
          options: const NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: NLatLng(37.5666, 126.9784),
              zoom: 15,
            ),
            locationButtonEnable: true, // 내 위치 버튼 활성화
          ),
          onMapReady: (controller) {
            debugPrint("네이버 지도가 준비되었습니다!");
          },
        ),
      ),
    );
  }
}
