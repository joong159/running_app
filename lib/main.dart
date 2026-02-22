import 'package:flutter/foundation.dart'; // debugPrint를 위해 필요해요
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 초기화 완료를 기다린 후 앱을 실행합니다.
  await NaverMapSdk.instance.initialize(
    clientId: 'e4er7uvr2b', // 네이버 클라우드 플랫폼에서 발급받은 클라이언트 ID로 변경하세요.
    onAuthFailed: (error) {
      debugPrint("인증 실패 사유: ${error.message}, 코드: ${error.code}");
    },
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
