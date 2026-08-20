import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../widgets/report_modal.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  
  LatLng _currentLocation = LocationService.defaultLocation;
  bool _isLocating = false;
  String _locationStatus = '현재 위치 안내 중';
  double? _accuracy;

  List<Map<String, dynamic>> _hazards = [];
  List<Map<String, dynamic>> _buildings = [];
  bool _isLoadingData = false;

  // Route Mode: 'pedestrian' | 'electric' | 'manual'
  String _selectedRouteMode = 'pedestrian';

  // Map Tapped Location for reporting
  LatLng? _selectedTappedLocation;

  // ==========================================
  // Real-time Movement Tracking & Sensor State
  // ==========================================
  bool _isTrackingRoute = false;
  final List<LatLng> _trackedPoints = [];
  double _totalDistanceMeters = 0.0;
  int _autoDetectedBumpsCount = 0;
  
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<UserAccelerometerEvent>? _accelStreamSub;
  DateTime _lastBumpTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSupabaseData();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _accelStreamSub?.cancel();
    super.dispose();
  }

  // Toggle live movement & bump collection
  void _toggleRouteTracking() {
    if (_isTrackingRoute) {
      _stopRouteTracking();
    } else {
      _startRouteTracking();
    }
  }

  void _startRouteTracking() {
    setState(() {
      _isTrackingRoute = true;
      _trackedPoints.clear();
      _totalDistanceMeters = 0.0;
      _autoDetectedBumpsCount = 0;
      _trackedPoints.add(_currentLocation);
    });

    // 1. Listen to continuous GPS stream
    _positionStreamSub = LocationService.getPositionStream().listen((position) {
      if (!mounted) return;
      final newPoint = LatLng(position.latitude, position.longitude);
      
      setState(() {
        if (_trackedPoints.isNotEmpty) {
          final lastPoint = _trackedPoints.last;
          final dist = const Distance().as(LengthUnit.Meter, lastPoint, newPoint);
          _totalDistanceMeters += dist;
        }
        _trackedPoints.add(newPoint);
        _currentLocation = newPoint;
        _accuracy = position.accuracy;
      });

      try {
        _mapController.move(newPoint, 17.0);
      } catch (_) {}
    });

    // 2. Listen to accelerometer for bump/vibration detection
    _accelStreamSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (!_isTrackingRoute) return;

      // Calculate acceleration magnitude (m/s^2)
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // Bump threshold: > 14.0 m/s^2 (vibration spike while moving)
      final now = DateTime.now();
      if (magnitude > 14.0 && now.difference(_lastBumpTime).inSeconds >= 4) {
        _lastBumpTime = now;
        _handleAutoDetectedBump(magnitude);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🟢 이동 경로 및 노면 단차 자동 수집이 시작되었습니다.'),
        backgroundColor: Colors.purple,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _stopRouteTracking() {
    _positionStreamSub?.cancel();
    _accelStreamSub?.cancel();

    setState(() {
      _isTrackingRoute = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🔴 수집 종료! 이동거리: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)}km, 자동 감지: $_autoDetectedBumpsCount건',
        ),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Handle auto-detected bump from accelerometer
  Future<void> _handleAutoDetectedBump(double magnitude) async {
    if (!mounted) return;

    setState(() {
      _autoDetectedBumpsCount++;
    });

    final autoHazard = {
      'type': 'damage',
      'latitude': _currentLocation.latitude,
      'longitude': _currentLocation.longitude,
      'step_height_cm': (magnitude * 0.4).roundToDouble(),
      'severity': magnitude > 20.0 ? 'high' : 'medium',
      'description': '이동 중 가속도 센서로 자동 감지된 노면 충격/단차 (충격도: ${magnitude.toStringAsFixed(1)})',
      'is_verified': false,
      'reported_at': DateTime.now().toUtc().toIso8601String(),
    };

    final success = await SupabaseService.insertHazard(autoHazard);
    if (success) {
      _loadSupabaseData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ 노면 단차 충격 감지! Supabase에 자동 제보되었습니다. (충격: ${magnitude.toStringAsFixed(1)})'),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _locationStatus = 'GPS 위치 수집 중...';
    });

    try {
      final Position? position = await LocationService.getCurrentPosition();

      if (mounted) {
        if (position != null) {
          final newLoc = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentLocation = newLoc;
            _accuracy = position.accuracy;
            _isLocating = false;
            _locationStatus = '현재 위치 수집 완료';
          });
          
          try {
            _mapController.move(newLoc, 16.5);
          } catch (e) {
            debugPrint('MapController move deferred: $e');
          }
        } else {
          setState(() {
            _isLocating = false;
            _locationStatus = 'GPS 미연동 (기본 작전역 위치 표시)';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationStatus = '위치 수집 오프라인 모드';
        });
      }
    }
  }

  Future<void> _loadSupabaseData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingData = true;
    });

    try {
      final hazards = await SupabaseService.fetchHazards();
      final buildings = await SupabaseService.fetchBuildings();

      if (mounted) {
        setState(() {
          _hazards = hazards;
          _buildings = buildings;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  void _openReportModal(LatLng loc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ReportModal(
        initialLocation: loc,
        onReportSubmitted: () {
          _loadSupabaseData();
        },
      ),
    );
  }

  void _showHazardDetail(Map<String, dynamic> hazard) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                const SizedBox(width: 8),
                Text(
                  '보행 위험 정보 (${hazard['type'] ?? '단차/파손'})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('• 단차 높이: ${hazard['step_height_cm'] ?? '-'} cm'),
            Text('• 심각도: ${hazard['severity'] ?? '기본'}'),
            Text('• 설명: ${hazard['description'] ?? '설명 없음'}'),
            Text('• 제보 시각: ${hazard['reported_at'] ?? '-'}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBuildingDetail(Map<String, dynamic> building) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, color: Colors.blue, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    building['name'] ?? '건물 정보',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('• 경사로(Ramp): ${building['has_ramp'] == true ? '있음' : '없음'}'),
            Text('• 승강기(Elevator): ${building['has_elevator'] == true ? '있음' : '없음'}'),
            Text('• 장애인 화장실: ${building['disabled_toilet'] == true ? '있음' : '없음'}'),
            Text('• 주출입문 유형: ${building['main_entrance_type'] ?? '정보 없음'}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Generate safe polyline routes based on mode
  List<Polyline> _getRoutePolylines() {
    final List<Polyline> list = [];

    // Live Recorded Trajectory Polyline (Purple line)
    if (_trackedPoints.length > 1) {
      list.add(
        Polyline(
          points: List.from(_trackedPoints),
          strokeWidth: 6.0,
          color: Colors.purple.shade600,
        ),
      );
    }

    // Jakjeon station -> Jakjeon Girls High School mock route points
    if (_selectedRouteMode == 'electric') {
      list.add(
        Polyline(
          points: const [
            LatLng(37.5346, 126.7225),
            LatLng(37.5350, 126.7230),
            LatLng(37.5360, 126.7240),
            LatLng(37.5375, 126.7248),
            LatLng(37.5385, 126.7240),
          ],
          strokeWidth: 5.0,
          color: Colors.blue.shade600,
        ),
      );
    } else if (_selectedRouteMode == 'manual') {
      list.add(
        Polyline(
          points: const [
            LatLng(37.5346, 126.7225),
            LatLng(37.5349, 126.7215),
            LatLng(37.5360, 126.7218),
            LatLng(37.5372, 126.7230),
            LatLng(37.5385, 126.7240),
          ],
          strokeWidth: 5.0,
          color: Colors.green.shade600,
        ),
      );
    } else {
      list.add(
        Polyline(
          points: const [
            LatLng(37.5346, 126.7225),
            LatLng(37.5360, 126.7235),
            LatLng(37.5385, 126.7240),
          ],
          strokeWidth: 4.0,
          color: Colors.orange.shade600,
        ),
      );
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/logo.png',
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.navigation, color: Colors.blue),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'FlatWay - 보행 수집 지도',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '데이터 새로고침',
            onPressed: () {
              _fetchCurrentLocation();
              _loadSupabaseData();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap Tile, Polyline & Marker Layers
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 16.5,
                minZoom: 5.0,
                maxZoom: 19.0,
                onTap: (tapPosition, point) {
                  setState(() {
                    _selectedTappedLocation = point;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.flatway_app',
                ),
                
                // Safe Route & Live Trajectory Polyline Layer
                PolylineLayer(
                  polylines: _getRoutePolylines(),
                ),

                MarkerLayer(
                  markers: [
                    // 1. Hazards markers (Orange/Red icons)
                    ..._hazards.where((h) => h['latitude'] != null && h['longitude'] != null).map((h) {
                      final lat = (h['latitude'] as num).toDouble();
                      final lng = (h['longitude'] as num).toDouble();
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showHazardDetail(h),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(Icons.warning, color: Colors.white, size: 22),
                          ),
                        ),
                      );
                    }),

                    // 2. Buildings markers (Blue icons)
                    ..._buildings.where((b) => b['latitude'] != null && b['longitude'] != null).map((b) {
                      final lat = (b['latitude'] as num).toDouble();
                      final lng = (b['longitude'] as num).toDouble();
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showBuildingDetail(b),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(Icons.business, color: Colors.white, size: 22),
                          ),
                        ),
                      );
                    }),

                    // 3. User Current Location marker (Blue pulse icon)
                    Marker(
                      point: _currentLocation,
                      width: 54,
                      height: 54,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isTrackingRoute
                              ? Colors.purple.withValues(alpha: 0.3)
                              : Colors.blue.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isTrackingRoute ? Colors.purple : Colors.blue,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _isTrackingRoute ? Colors.purple.shade700 : Colors.blue.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. Map Tapped Location Marker (Pin for report)
                    if (_selectedTappedLocation != null)
                      Marker(
                        point: _selectedTappedLocation!,
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _openReportModal(_selectedTappedLocation!),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.purple,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                            ),
                            child: const Icon(Icons.add_location_alt, color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Top Control Panel: Tracking Status & Mode Selector
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Live Route Tracking Control Bar
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  color: _isTrackingRoute ? Colors.purple.shade900 : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: (_isLocating || _isLoadingData)
                              ? const CircularProgressIndicator(strokeWidth: 2.5)
                              : Icon(
                                  _isTrackingRoute ? Icons.route : Icons.gps_fixed,
                                  color: _isTrackingRoute ? Colors.amberAccent : Colors.blue,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isTrackingRoute
                                    ? '실시간 이동 경로 수집 중 (${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km)'
                                    : _locationStatus,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _isTrackingRoute ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (_isTrackingRoute)
                                Text(
                                  '포인트: ${_trackedPoints.length}개 | 충격 자동감지: $_autoDetectedBumpsCount건',
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                )
                              else if (_accuracy != null)
                                Text(
                                  'GPS 오차 범위: ±${_accuracy!.toStringAsFixed(0)}m',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _toggleRouteTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isTrackingRoute ? Colors.red : Colors.purple.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Text(_isTrackingRoute ? '수집 중단' : '경로 수집'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Movement Mode Selector (보행자 / 전동휠체어 / 수동휠체어)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRouteModeButton('pedestrian', '🚶 보행자', Colors.orange),
                        _buildRouteModeButton('electric', '⚡ 전동휠체어', Colors.blue),
                        _buildRouteModeButton('manual', '♿ 수동휠체어', Colors.green),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Info Summary & Tapped Location Action Chip
          Positioned(
            bottom: 24,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedTappedLocation != null) ...[
                  ElevatedButton.icon(
                    onPressed: () => _openReportModal(_selectedTappedLocation!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.add_location),
                    label: const Text('선택한 위치 단차/파손 제보'),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text('위험 ${_hazards.length}건', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(width: 12),
                      const Icon(Icons.business, color: Colors.lightBlueAccent, size: 16),
                      const SizedBox(width: 4),
                      Text('건물 ${_buildings.length}개', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openReportModal(_currentLocation),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.report_problem),
        label: const Text('현재 위치 제보'),
      ),
    );
  }

  Widget _buildRouteModeButton(String modeKey, String label, Color color) {
    final isSelected = _selectedRouteMode == modeKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRouteMode = modeKey;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Colors.black87,
          ),
        ),
      ),
    );
  }
}
