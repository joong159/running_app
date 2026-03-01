import 'package:flutter/material.dart';
import 'package:running_app/screens/profile_setup_screen.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        final isNew = await _authService.isNewUser(user);
        if (isNew) {
          // 새 유저면 프로필 설정 화면으로
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ProfileSetupScreen(user: user),
            ),
          );
        } else {
          // 기존 유저면 바로 메인 화면으로
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapScreen()),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('로그인에 실패했습니다: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '가온길',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            const Text('세상의 중심을 달리는 길', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 100),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    onPressed: _handleGoogleSignIn,
                    icon: const Icon(Icons.login, color: Colors.red),
                    label: const Text('Google 계정으로 시작하기'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
