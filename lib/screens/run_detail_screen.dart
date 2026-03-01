import 'dart:io';
import 'dart:math';
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

class RunDetailScreen extends StatefulWidget {
  final RunRecord record;

  const RunDetailScreen({super.key, required this.record});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  NaverMapController? _mapController; // 📍 지도 컨트롤러 추가
  List<FlSpot> _elevationSpots = []; // 📍 고도 데이터 포인트

  @override
  void initState() {
    super.initState();
    _generateMockElevationData(); // 고도 데이터 생성 (데모용)
  }

  Future<void> _shareRecord(BuildContext context) async {
    // 1. 지도 스냅샷 캡처
    if (_mapController == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final snapshotFile = await _mapController!.takeSnapshot(
        showControls: false,
      );
      final mapImage = await snapshotFile.readAsBytes();

      // 2. 공유 카드 위젯 생성
      final shareCard = _ShareCard(
        mapImage: mapImage,
        distance: widget.record.totalDistanceKm.toStringAsFixed(2),
        time: _formatDuration(widget.record.duration),
        pace: widget.record.pace,
        calories: widget.record.calories,
        date: widget.record.date,
      );

      // 3. 위젯을 이미지로 캡처
      final imageBytes = await _screenshotController.captureFromWidget(
        Material(child: shareCard),
        pixelRatio: 2.0,
        targetSize: const Size(540, 960),
      );

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/run_record_share.png').create();
      await file.writeAsBytes(imageBytes);

      if (mounted) Navigator.pop(context); // 로딩 닫기

      await Share.shareXFiles([XFile(file.path)], text: '나의 러닝 기록 🏃‍♂️ #가온길');
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('공유 실패: $e')));
      }
    }
  }

  Future<void> _deleteRecord(BuildContext context) async {
    if (widget.record.id == null) {
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
        await _firestoreService.deleteRun(
          widget.record.id!,
          user.uid,
          widget.record,
        );
        if (context.mounted) {
          Navigator.pop(context); // 상세 화면 닫기
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('기록이 삭제되었습니다.')));
        }
      }
    }
  }

  Future<void> _sharePaceTable(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 캡처할 위젯 생성 (흰색 배경의 깔끔한 스타일)
      final tableWidget = Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '구간별 페이스 기록',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.record.date.year}년 ${widget.record.date.month}월 ${widget.record.date.day}일',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // 기존 테이블 위젯 재사용 (너비 꽉 차게)
            SizedBox(width: double.infinity, child: _buildPaceTable()),
            const SizedBox(height: 24),
            const Text(
              'GAONGIL RUNNING',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );

      final imageBytes = await _screenshotController.captureFromWidget(
        Material(child: tableWidget),
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.0,
      );

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/pace_table.png').create();
      await file.writeAsBytes(imageBytes);

      if (mounted) Navigator.pop(context); // 로딩 닫기

      await Share.shareXFiles([
        XFile(file.path),
      ], text: '나의 구간별 페이스 기록 📊 #가온길');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 저장 실패: $e')));
      }
    }
  }

  /// 📍 고도 데이터 생성 (실제 데이터가 없을 경우 시뮬레이션)
  void _generateMockElevationData() {
    // 실제 앱에서는 record.elevations 등을 사용해야 합니다.
    // 여기서는 총 거리에 따라 자연스러운 고도 변화를 만듭니다.
    final totalKm = widget.record.totalDistanceKm;
    if (totalKm <= 0) return;

    final points = 50; // 그래프 포인트 개수
    final random = Random(42); // 고정 시드 (항상 같은 그래프 모양 유지)
    double currentElevation = 30.0; // 시작 고도 (m)

    _elevationSpots = List.generate(points, (index) {
      final x = (index / (points - 1)) * totalKm;
      // 랜덤하게 오르락 내리락
      final change = (random.nextDouble() - 0.5) * 5;
      currentElevation += change;
      if (currentElevation < 0) currentElevation = 0; // 해수면 아래 방지

      return FlSpot(x, currentElevation);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 📍 그래프 Y축 범위 자동 조절 (데이터 최소/최대값 + 여유 공간)
    double minY = 0;
    double maxY = 10;
    if (widget.record.paceSegments.isNotEmpty) {
      double minVal = widget.record.paceSegments.reduce(
        (curr, next) => curr < next ? curr : next,
      );
      double maxVal = widget.record.paceSegments.reduce(
        (curr, next) => curr > next ? curr : next,
      );
      minY = (minVal - 0.5).floorToDouble(); // 최소값보다 0.5(30초) 아래
      if (minY < 0) minY = 0;
      maxY = (maxVal + 0.5).ceilToDouble(); // 최대값보다 0.5(30초) 위
    }

    // 📍 X축 레이블 간격 설정 (데이터가 많을 경우 겹치지 않게 조절)
    double interval = 1;
    if (widget.record.paceSegments.length > 10) {
      interval = (widget.record.paceSegments.length / 6).ceilToDouble();
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
                if (widget.record.routePath.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _FullScreenMapScreen(
                            routePath: widget.record.routePath,
                            totalDistanceKm: widget.record.totalDistanceKm,
                            duration: widget.record.duration,
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
                              _mapController = controller;
                              // 경로 그리기
                              final pathOverlay = NPathOverlay(
                                id: 'history_path',
                                coords: widget.record.routePath,
                                width: 5,
                                color: Colors.green,
                              );
                              controller.addOverlay(pathOverlay);

                              // 경로 전체가 보이도록 카메라 이동
                              final bounds = NLatLngBounds.from(
                                widget.record.routePath,
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
                          '${widget.record.totalDistanceKm.toStringAsFixed(2)} km',
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
                              _formatDuration(widget.record.duration),
                            ),
                            _buildInfoItem('페이스', widget.record.pace),
                            _buildInfoItem('칼로리', '${widget.record.calories}'),
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
                  child: widget.record.paceSegments.isEmpty
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
                                  spots: widget.record.paceSegments
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
                                  curveSmoothness:
                                      0.5, // 📍 곡선을 더 부드럽게 설정 (기본값 0.35)
                                  preventCurveOverShooting:
                                      true, // 📍 곡선이 데이터 점을 과도하게 벗어나지 않도록 방지
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

                // 📍 고도 그래프 영역 추가
                if (_elevationSpots.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Text(
                    '⛰️ 고도 변화',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(height: 200, child: _buildElevationChart()),
                ],

                // 📍 표 영역 추가
                if (widget.record.paceSegments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📊 상세 구간 기록',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_rounded),
                        tooltip: '이미지로 저장',
                        onPressed: () => _sharePaceTable(context),
                      ),
                    ],
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

  Widget _buildElevationChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false), // 축 라벨 숨김 (깔끔하게)
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.blueGrey.withOpacity(0.8),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}m',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _elevationSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.blueGrey,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blueGrey.withOpacity(0.4),
                  Colors.blueGrey.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        // Y축 범위 설정 (그래프 모양 예쁘게)
        minY: _elevationSpots.map((e) => e.y).reduce(min) - 5,
        maxY: _elevationSpots.map((e) => e.y).reduce(max) + 5,
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
      rows: widget.record.paceSegments.asMap().entries.map((entry) {
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

// ─────────────────────────────────────
// 인스타그램 공유 카드 위젯 (MapScreen과 동일한 디자인)
// ─────────────────────────────────────
class _ShareCard extends StatelessWidget {
  final Uint8List mapImage;
  final String distance;
  final String time;
  final String pace;
  final int calories;
  final DateTime date;

  const _ShareCard({
    required this.mapImage,
    required this.distance,
    required this.time,
    required this.pace,
    required this.calories,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 배경: 지도 캡처
          Image.memory(mapImage, fit: BoxFit.cover),

          // 2. 그라데이션 오버레이
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.15, 0.6, 1.0],
              ),
            ),
          ),

          // 3. 상단 날짜 및 요일
          Positioned(
            top: 60,
            left: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  _getDayOfWeek(date.weekday),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 4. 하단 스탯 정보
          Positioned(
            bottom: 50,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distance,
                      style: const TextStyle(
                        color: Color(0xFFCCFF00),
                        fontSize: 96,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        height: 0.9,
                        letterSpacing: -2.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'km',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(width: 60, height: 4, color: const Color(0xFFCCFF00)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem('TIME', time),
                    _buildStatItem('PACE', pace),
                    _buildStatItem('KCAL', '$calories'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  String _getDayOfWeek(int weekday) {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[weekday - 1];
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
