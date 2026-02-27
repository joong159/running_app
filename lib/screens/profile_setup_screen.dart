import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:running_app/screens/map_screen.dart';
import '../services/auth_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final User user;
  const ProfileSetupScreen({super.key, required this.user});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  // Form fields
  int? _age;
  String? _gender;
  String? _region;

  bool _isLoading = false;

  Future<void> _submitProfile() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      try {
        await _authService.createUserProfile(
          user: widget.user,
          name: widget.user.displayName ?? '사용자',
          age: _age!,
          gender: _gender!,
          region: _region!,
        );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('프로필 저장에 실패했습니다: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 설정')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('가온길에 오신 것을 환영합니다!', style: TextStyle(fontSize: 20)),
              const Text('랭킹 서비스를 위해 추가 정보를 입력해주세요.'),
              const SizedBox(height: 32),
              TextFormField(
                decoration: const InputDecoration(labelText: '나이'),
                keyboardType: TextInputType.number,
                validator: (val) => val!.isEmpty ? '나이를 입력하세요.' : null,
                onSaved: (val) => _age = int.tryParse(val!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '성별'),
                value: _gender,
                items: ['남성', '여성']
                    .map(
                      (label) =>
                          DropdownMenuItem(value: label, child: Text(label)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _gender = val),
                validator: (val) => val == null ? '성별을 선택하세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: '주 활동 지역 (예: 서울시 강남구)',
                ),
                validator: (val) => val!.isEmpty ? '지역을 입력하세요.' : null,
                onSaved: (val) => _region = val,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('가온길 시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
