import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'history_screen.dart';
import 'community_screen.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 스포츠 브랜드 느낌의 다크 테마 & 네온 포인트
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 짙은 검정 배경
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 헤더 (로고 및 로그아웃)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'GAONGIL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.grey),
                    onPressed: () async {
                      await AuthService().signOut();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // 메인 문구
              const Text(
                'KEEP\nRUNNING.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  height: 1.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '오늘도 당신의 길을 만드세요.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
              _buildWeeklyDistance(),
              const Spacer(),

              // 메뉴 버튼들
              _buildMenuButton(
                context,
                title: 'RUN NOW',
                subtitle: '달리기 시작하기',
                icon: Icons.directions_run,
                color: const Color(0xFFCCFF00), // 네온 라임
                textColor: Colors.black,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MapScreen()),
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuButton(
                context,
                title: 'HISTORY',
                subtitle: '나의 기록 보기',
                icon: Icons.bar_chart,
                color: const Color(0xFF2C2C2C),
                textColor: Colors.white,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuButton(
                context,
                title: 'COMMUNITY',
                subtitle: '러너들과 소통하기',
                icon: Icons.people_alt_outlined,
                color: const Color(0xFF2C2C2C),
                textColor: Colors.white,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CommunityScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.2),
        child: Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(icon, color: textColor, size: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyDistance() {
    final user = AuthService().currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, double>>(
      future: FirestoreService().getWeeklyStats(user.uid),
      builder: (context, snapshot) {
        String distanceStr = '0.0';
        if (snapshot.hasData && snapshot.data != null) {
          distanceStr = snapshot.data!['thisWeek']!.toStringAsFixed(1);
        }

        return Container(
          margin: const EdgeInsets.only(top: 30),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        distanceStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'km',
                        style: TextStyle(
                          color: Color(0xFFCCFF00), // 네온 라임
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFF00).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.show_chart,
                  color: Color(0xFFCCFF00),
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
