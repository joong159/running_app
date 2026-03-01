import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../models/run_record.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class RunDetailScreen extends StatelessWidget {
  final RunRecord record;
  final ScreenshotController _screenshotController = ScreenshotController();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  RunDetailScreen({super.key, required this.record});

  Future<void> _shareRecord(BuildContext context) async {
    final capturedImage = await _screenshotController.capture();
    if (capturedImage == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/run_record.png').create();
      await file.writeAsBytes(capturedImage);

      await Share.shareXFiles([XFile(file.path)], text: '나의 러닝 기록 🏃‍♂️');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('공유 실패: $e')));
      }
    }
  }

  Future<void> _deleteRecord(BuildContext context) async {
    if (record.id == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제할 수 없는 기록입니다.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('정말로 이 기록을 삭제하시겠습니까?\n삭제된 기록은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = _authService.currentUser;
      if (user != null) {
        await _firestoreService.deleteRun(record.id!, user.uid, record);
        if (context.mounted) {
          Navigator.pop(context); // 상세 화면 닫기
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('기록이 삭제되었습니다.')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📍 그래프 Y축 범위 자동 조절 (데이터 최소/최대값 + 여유 공간)
    double minY = 0;
    double maxY = 10;
    if (record.paceSegments.isNotEmpty) {
      double minVal = record.paceSegments.reduce(
        (curr, next) => curr < next ? curr : next,
      );
      double maxVal = record.paceSegments.reduce(
        (curr, next) => curr > next ? curr : next,
      );
      minY = (minVal - 0.5).floorToDouble(); // 최소값보다 0.5(30초) 아래
      if (minY < 0) minY = 0;
      maxY = (maxVal + 0.5).ceilToDouble(); // 최대값보다 0.5(30초) 위
    }

    // 📍 X축 레이블 간격 설정 (데이터가 많을 경우 겹치지 않게 조절)
    double interval = 1;
    if (record.paceSegments.length > 10) {
      interval = (record.paceSegments.length / 6).ceilToDouble();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('기록 상세'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareRecord(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteRecord(context),
          ),
        ],
      ),
      body: Screenshot(
        controller: _screenshotController,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 📍 지도 (Lite Mode) - 경로 표시
                if (record.routePath.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _FullScreenMapScreen(
                            routePath: record.routePath,
                            totalDistanceKm: record.totalDistanceKm,
                            duration: record.duration,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      height: 250,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        children: [
                          NaverMap(
                            options: const NaverMapViewOptions(
                              liteModeEnable: true, // 라이트 모드 (가볍게 표시)
                              scrollGesturesEnable: false,
                              zoomGesturesEnable: false,
                              tiltGesturesEnable: false,
                              rotationGesturesEnable: false,
                              scaleBarEnable: false,
                              logoClickEnable: false,
                            ),
                            onMapReady: (controller) {
                              // 경로 그리기
                              final pathOverlay = NPathOverlay(
                                id: 'history_path',
                                coords: record.routePath,
                                width: 5,
                                color: Colors.green,
                              );
                              controller.addOverlay(pathOverlay);

                              // 경로 전체가 보이도록 카메라 이동
                              final bounds = NLatLngBounds.from(
                                record.routePath,
                              );
                              controller.updateCamera(
                                NCameraUpdate.fitBounds(
                                  bounds,
                                  padding: const EdgeInsets.all(20),
                                ),
                              );
                            },
                          ),
                          // 터치 이벤트를 잡기 위한 투명 레이어
                          Container(color: Colors.transparent),
                          // 확대 아이콘 표시
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.fullscreen,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 요약 카드
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Text(
                          '${record.totalDistanceKm.toStringAsFixed(2)} km',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildInfoItem(
                              '시간',
                              _formatDuration(record.duration),
                            ),
                            _buildInfoItem('페이스', record.pace),
                            _buildInfoItem('칼로리', '${record.calories}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  '🏃‍♂️ 1km 구간별 페이스',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 그래프 영역
                SizedBox(
                  height: 300,
                  child: record.paceSegments.isEmpty
                      ? const Center(
                          child: Text('구간 기록이 부족합니다. (1km 이상 주행 필요)'),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(
                            right: 16.0,
                            top: 10.0,
                            bottom: 10.0,
                          ),
                          child: LineChart(
                            LineChartData(
                              minY: minY,
                              maxY: maxY,
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (touchedSpot) {
                                    if (maxY == minY) return Colors.green;
                                    final t =
                                        (touchedSpot.y - minY) / (maxY - minY);
                                    return Color.lerp(
                                          Colors.green,
                                          Colors.red,
                                          t.clamp(0.0, 1.0),
                                        ) ??
                                        Colors.green;
                                  },
                                  getTooltipItems:
                                      (List<LineBarSpot> touchedBarSpots) {
                                        return touchedBarSpots.map((barSpot) {
                                          return LineTooltipItem(
                                            _formatPace(barSpot.y),
                                            const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        }).toList();
                                      },
                                ),
                              ),
                              gridData: const FlGridData(
                                show: true,
                                drawVerticalLine: true,
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value % 1 != 0)
                                        return const SizedBox.shrink();
                                      return Text(
                                        '${value.toInt()}km',
                                        style: const TextStyle(fontSize: 12),
                                      );
                                    },
                                    interval: interval,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) => Text(
                                      '${value.toStringAsFixed(1)}분',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    reservedSize: 40,
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: record.paceSegments
                                      .asMap()
                                      .entries
                                      .map(
                                        (e) => FlSpot(
                                          (e.key + 1).toDouble(),
                                          e.value,
                                        ),
                                      )
                                      .toList(),
                                  isCurved: true,
                                  gradient: const LinearGradient(
                                    colors: [Colors.green, Colors.red],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  barWidth: 4,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.green.withOpacity(0.3),
                                        Colors.red.withOpacity(0.3),
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                // 📍 표 영역 추가
                if (record.paceSegments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '📊 상세 구간 기록',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildPaceTable(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaceTable() {
    return DataTable(
      headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
      columns: const [
        DataColumn(
          label: Text('구간', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        DataColumn(
          label: Text('페이스', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
      rows: record.paceSegments.asMap().entries.map((entry) {
        final index = entry.key;
        final km = index + 1;
        final paceVal = entry.value;
        return DataRow(
          // 짝수 행(인덱스 1, 3, 5...)에 연한 회색 배경 적용하여 가독성 향상
          color: (index % 2 != 0)
              ? MaterialStateProperty.all(Colors.grey[100])
              : null,
          cells: [
            DataCell(Text('${km}km')),
            DataCell(Text(_formatPace(paceVal))),
          ],
        );
      }).toList(),
    );
  }

  String _formatPace(double paceVal) {
    final int minutes = paceVal.toInt();
    final int seconds = ((paceVal - minutes) * 60).round();
    return "$minutes'${seconds.toString().padLeft(2, '0')}''";
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _FullScreenMapScreen extends StatefulWidget {
  final List<NLatLng> routePath;
  final double totalDistanceKm;
  final Duration duration;

  const _FullScreenMapScreen({
    required this.routePath,
    required this.totalDistanceKm,
    required this.duration,
  });

  @override
  State<_FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<_FullScreenMapScreen>
    with SingleTickerProviderStateMixin {
  NaverMapController? _mapController;
  late AnimationController _animationController;
  NMarker? _runnerMarker;
  List<double> _cumulativeDistances = [];
  double _totalPathDistance = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _calculateDistances();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(_onAnimationTick);

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        setState(() => _isPlaying = false);
      }
    });
  }

  void _calculateDistances() {
    if (widget.routePath.isEmpty) return;
    _cumulativeDistances = [0.0];
    double total = 0.0;
    for (int i = 0; i < widget.routePath.length - 1; i++) {
      final p1 = widget.routePath[i];
      final p2 = widget.routePath[i + 1];
      final dist = Geolocator.distanceBetween(
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );
      total += dist;
      _cumulativeDistances.add(total);
    }
    _totalPathDistance = total;
  }

  void _onAnimationTick() {
    if (_mapController == null || _totalPathDistance == 0) return;
    final t = _animationController.value;
    final targetDist = t * _totalPathDistance;

    int index = 0;
    for (int i = 0; i < _cumulativeDistances.length - 1; i++) {
      if (_cumulativeDistances[i + 1] >= targetDist) {
        index = i;
        break;
      }
    }

    if (t >= 1.0) index = widget.routePath.length - 2;
    if (index < 0) index = 0;

    final p1 = widget.routePath[index];
    final p2 = widget.routePath[index + 1];
    final d1 = _cumulativeDistances[index];
    final d2 = _cumulativeDistances[index + 1];
    final segmentDist = d2 - d1;

    double fraction = 0.0;
    if (segmentDist > 0) {
      fraction = (targetDist - d1) / segmentDist;
    }
    fraction = fraction.clamp(0.0, 1.0);

    final lat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
    final lng = p1.longitude + (p2.longitude - p1.longitude) * fraction;
    final newPos = NLatLng(lat, lng);

    if (_runnerMarker == null) {
      _runnerMarker = NMarker(
        id: 'runner',
        position: newPos,
        iconTintColor: Colors.purpleAccent,
        caption: const NOverlayCaption(text: "🏃"),
      );
      _mapController!.addOverlay(_runnerMarker!);
    } else {
      _runnerMarker!.setPosition(newPos);
    }

    _mapController!.updateCamera(NCameraUpdate.withParams(target: newPos));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleAnimation() {
    if (_animationController.isAnimating) {
      _animationController.stop();
      setState(() => _isPlaying = false);
    } else {
      if (_animationController.value == 1.0) {
        _animationController.reset();
      }
      _animationController.forward();
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('전체 경로')),
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              mapType: NMapType.basic,
              locationButtonEnable: false,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              if (widget.routePath.isEmpty) return;

              final pathOverlay = NPathOverlay(
                id: 'full_history_path',
                coords: widget.routePath,
                width: 5,
                color: Colors.green,
                outlineWidth: 2,
                outlineColor: Colors.white,
              );
              controller.addOverlay(pathOverlay);

              // 시작점 마커 (파란색)
              final startMarker = NMarker(
                id: 'start_point',
                position: widget.routePath.first,
                caption: const NOverlayCaption(text: "시작"),
                iconTintColor: Colors.blue,
              );

              // 도착점 마커 (빨간색)
              final endMarker = NMarker(
                id: 'end_point',
                position: widget.routePath.last,
                caption: const NOverlayCaption(text: "도착"),
                iconTintColor: Colors.red,
              );

              controller.addOverlayAll({startMarker, endMarker});

              final bounds = NLatLngBounds.from(widget.routePath);
              controller.updateCamera(
                NCameraUpdate.fitBounds(
                  bounds,
                  padding: const EdgeInsets.all(40),
                ),
              );
            },
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoItem(
                    "거리",
                    "${widget.totalDistanceKm.toStringAsFixed(2)} km",
                  ),
                  _buildInfoItem("시간", _formatDuration(widget.duration)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleAnimation,
        backgroundColor: Colors.white,
        child: Icon(
          _isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.green,
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
