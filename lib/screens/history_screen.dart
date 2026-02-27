import 'package:flutter/material.dart';
import '../models/run_record.dart';
import '../services/run_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<RunRecord>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = RunHistoryService().getRunHistory();
  }

  /// 날짜별로 기록을 그룹화하는 함수
  Map<String, List<RunRecord>> _groupRecordsByDate(List<RunRecord> records) {
    final Map<String, List<RunRecord>> grouped = {};
    for (var record in records) {
      // 날짜 키 생성 (예: 2024년 5월 20일)
      final dateKey =
          "${record.date.year}년 ${record.date.month}월 ${record.date.day}일";
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(record);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 기록')),
      body: FutureBuilder<List<RunRecord>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('오류 발생: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('저장된 운동 기록이 없습니다.'));
          }

          final records = snapshot.data!;
          // 최신순 정렬
          records.sort((a, b) => b.date.compareTo(a.date));

          final groupedRecords = _groupRecordsByDate(records);
          final dateKeys = groupedRecords.keys.toList();

          return ListView.builder(
            itemCount: dateKeys.length,
            itemBuilder: (context, index) {
              final date = dateKeys[index];
              final dayRecords = groupedRecords[date]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateHeader(date),
                  ...dayRecords.map((record) => _buildRecordTile(record)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDateHeader(String date) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[200],
      child: Text(
        date,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildRecordTile(RunRecord record) {
    final timeStr =
        "${record.date.hour.toString().padLeft(2, '0')}:${record.date.minute.toString().padLeft(2, '0')}";
    final durationStr = _formatDuration(record.duration);

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.green,
        child: Icon(Icons.directions_run, color: Colors.white),
      ),
      title: Text('${record.totalDistanceKm.toStringAsFixed(2)} km'),
      subtitle: Text('$timeStr 시작 | $durationStr 소요 | ${record.calories} kcal'),
      trailing: Text(
        record.pace,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
