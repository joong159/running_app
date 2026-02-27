import 'dart:convert';
import 'package:running_app/models/run_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RunHistoryService {
  static const _key = 'run_history';

  Future<void> saveRun(RunRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_key) ?? [];
    // 최신 기록이 맨 위로 오도록 insert(0, ...) 사용
    history.insert(0, jsonEncode(record.toJson()));
    await prefs.setStringList(_key, history);
  }

  Future<List<RunRecord>> getRunHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(_key) ?? [];
    return history
        .map((recordJson) => RunRecord.fromJson(jsonDecode(recordJson)))
        .toList();
  }
}
