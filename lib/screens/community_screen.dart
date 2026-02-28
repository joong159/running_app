import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:running_app/services/firestore_service.dart';
import 'package:running_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('가온길 커뮤니티'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '피드'),
              Tab(text: '크루 모집'),
            ],
            indicatorColor: Colors.green,
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
          ),
        ),
        body: TabBarView(children: [_buildFeedTab(), _buildCrewTab()]),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // TODO: 크루 생성 또는 글쓰기 화면 연결
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('크루 생성 기능 준비 중입니다!')));
          },
          backgroundColor: Colors.green,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  // ─────────────────────────────────────
  // 1. 피드 탭 (러닝 기록 공유)
  // ─────────────────────────────────────
  Widget _buildFeedTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getCommunityFeed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('아직 공유된 기록이 없어요.'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildFeedCard(doc.id, data);
          },
        );
      },
    );
  }

  // ─────────────────────────────────────
  // 2. 크루 탭 (모집 게시판)
  // ─────────────────────────────────────
  Widget _buildCrewTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getCrews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('모집 중인 크루가 없습니다.'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.group)),
              title: Text(data['name'] ?? '이름 없음'),
              subtitle: Text(data['description'] ?? ''),
              trailing: Text(
                '${data['currentMembers']}/${data['maxMembers']}명',
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedCard(String docId, Map<String, dynamic> data) {
    final distance = (data['distanceKm'] as num).toStringAsFixed(2);
    final pace = data['pace'] as String;
    final userName = data['userName'] as String;
    final ageGroup = data['userAgeGroup'] as int;
    final gender = data['userGender'] as String;
    final imageUrl = data['mapImageUrl'] as String;
    final likes = data['likes'] as int? ?? 0;
    final likedBy = List<String>.from(data['likedBy'] ?? []);
    final currentUser = _authService.currentUser;
    final isLiked = currentUser != null && likedBy.contains(currentUser.uid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$ageGroup대 $gender',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 지도 이미지
          Image.network(
            imageUrl,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              return progress == null
                  ? child
                  : const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
            },
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                height: 200,
                child: Center(child: Icon(Icons.error)),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$distance km  |  페이스 $pace',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (currentUser != null) {
                          _firestoreService.toggleLike(docId, currentUser.uid);
                        }
                      },
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.grey,
                      ),
                    ),
                    Text(likes.toString()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
