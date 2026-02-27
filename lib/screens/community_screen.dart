import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:running_app/services/firestore_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가온길 커뮤니티')),
      body: StreamBuilder<QuerySnapshot>(
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
              final data = docs[index].data() as Map<String, dynamic>;
              return _buildFeedCard(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> data) {
    final distance = (data['distanceKm'] as num).toStringAsFixed(2);
    final pace = data['pace'] as String;
    final userName = data['userName'] as String;
    final ageGroup = data['userAgeGroup'] as int;
    final gender = data['userGender'] as String;
    final imageUrl = data['mapImageUrl'] as String;

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
                      onPressed: () {},
                      icon: const Icon(Icons.favorite_border),
                    ),
                    Text((data['likes'] as int? ?? 0).toString()),
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
