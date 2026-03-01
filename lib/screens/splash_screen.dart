import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 다크 테마 배경
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 아이콘 (네온 효과)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCCFF00), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCCFF00).withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_run,
                size: 80,
                color: Color(0xFFCCFF00), // 네온 라임
              ),
            ),
            const SizedBox(height: 32),
            // 앱 이름
            const Text(
              'GAONGIL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            // 슬로건
            Text(
              'RUN YOUR WAY',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                letterSpacing: 4.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
