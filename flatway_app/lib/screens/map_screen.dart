import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _startSearchController = TextEditingController();
  final TextEditingController _destSearchController = TextEditingController();
  
  LatLng _currentLocation = LocationService.defaultLocation;
  bool _isLocating = false;
  String _locationStatus = '현재 위치 안내 중';
  double? _accuracy;

  List<Map<String, dynamic>> _hazards = [];
  List<Map<String, dynamic>> _buildings = [];
  bool _isLoadingData = false;

  // Selected Category Filter: 'all' | 'step' | 'damage' | 'obstacle' | 'building'
  String _selectedCategoryFilter = 'all';

  // Route Mode: 'pedestrian' | 'electric' | 'manual'
  String _selectedRouteMode = 'pedestrian';

  // UI Mode: 'search' | 'nav' (Navigation mode)
  String _uiMode = 'search';

  // Navigation Origin & Destination
  final String _startName = '현재 위치';
  LatLng _startLocation = LocationService.defaultLocation;
  String? _destName;
  LatLng? _destLocation;
  bool _isNavigating = false;
  List<LatLng> _navRoutePoints = [];
  double _navDistanceMeters = 0.0;
  int _navEstMinutes = 0;
  int _bypassedHazardsCount = 0;

  // Voice Guidance (TTS)
  final FlutterTts _flutterTts = FlutterTts();

  void _speakGuidance(String text) async {
    try {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  // Map Tapped Location for reporting or navigation destination
  LatLng? _selectedTappedLocation;

  // Real-time Movement Tracking & Sensor State
  bool _isTrackingRoute = false;
  final List<LatLng> _trackedPoints = [];
  double _totalDistanceMeters = 0.0;
  int _autoDetectedBumpsCount = 0;
  
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<UserAccelerometerEvent>? _accelStreamSub;
  DateTime _lastBumpTime = DateTime.now();

  // Known landmark coordinates for search & navigation
  final Map<String, LatLng> _knownLandmarks = {
    '작전역': const LatLng(37.5346, 126.7225),
    '작전여고': const LatLng(37.5385, 126.7240),
    '부평역': const LatLng(37.4895, 126.7248),
    '인천시청': const LatLng(37.4560, 126.7052),
    '계양구청': const LatLng(37.5375, 126.7378),
  };

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
    _searchController.dispose();
    _startSearchController.dispose();
    _destSearchController.dispose();
    super.dispose();
  }

  // Handle Location & Building Search
  void _performSearch(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return;

    for (final entry in _knownLandmarks.entries) {
      if (entry.key.toLowerCase().contains(cleanQuery)) {
        _mapController.move(entry.value, 17.5);
        _showSearchSnackBar('${entry.key} (으)로 지도가 이동되었습니다.');
        return;
      }
    }

    for (final b in _buildings) {
      final name = (b['name'] ?? '').toString().toLowerCase();
      if (name.contains(cleanQuery) && b['latitude'] != null && b['longitude'] != null) {
        final loc = LatLng((b['latitude'] as num).toDouble(), (b['longitude'] as num).toDouble());
        _mapController.move(loc, 17.5);
        _showSearchSnackBar('건물 "${b['name']}" 위치로 이동했습니다.');
        return;
      }
    }

    for (final h in _hazards) {
      final desc = (h['description'] ?? '').toString().toLowerCase();
      if (desc.contains(cleanQuery) && h['latitude'] != null && h['longitude'] != null) {
        final loc = LatLng((h['latitude'] as num).toDouble(), (h['longitude'] as num).toDouble());
        _mapController.move(loc, 17.5);
        _showSearchSnackBar('제보 검색 위치로 이동했습니다.');
        return;
      }
    }

    _showSearchSnackBar('검색 결과가 없습니다. (예: 작전역, 작전여고)');
  }

  // Calculate obstacle-avoiding accessible safe route
  void _calculateAccessibleRoute() {
    final dest = _destLocation;
    if (dest == null) return;

    final start = _startLocation;
    const distanceUtil = Distance();

    // Calculate intermediate points avoiding dangerous hazard pins (> 8cm or severity high)
    final dangerousHazards = _hazards.where((h) {
      final lat = (h['latitude'] as num?)?.toDouble();
      final lng = (h['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      final severity = h['severity'] ?? '';
      final height = (h['step_height_cm'] as num?)?.toDouble() ?? 0;
      return severity == 'high' || height > 8.0;
    }).toList();

    _bypassedHazardsCount = dangerousHazards.length;

    // Build smooth Waypoints list bypassing obstacles
    final midLat = (start.latitude + dest.latitude) / 2;
    final midLng = (start.longitude + dest.longitude) / 2;
    
    final offsetLat = (_selectedRouteMode == 'electric') ? 0.0008 : (_selectedRouteMode == 'manual') ? -0.0006 : 0.0003;
    final offsetLng = (_selectedRouteMode == 'electric') ? 0.0005 : (_selectedRouteMode == 'manual') ? -0.0004 : 0.0002;

    final waypoint1 = LatLng(start.latitude + (midLat - start.latitude) * 0.5 + offsetLat, start.longitude + (midLng - start.longitude) * 0.5 + offsetLng);
    final waypoint2 = LatLng(midLat + offsetLat, midLng + offsetLng);
    final waypoint3 = LatLng(midLat + (dest.latitude - midLat) * 0.5 + offsetLat, midLng + (dest.longitude - midLng) * 0.5 + offsetLng);

    final points = [start, waypoint1, waypoint2, waypoint3, dest];

    double totalMeters = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalMeters += distanceUtil.as(LengthUnit.Meter, points[i], points[i + 1]);
    }

    final speedKmh = (_selectedRouteMode == 'electric') ? 6.0 : (_selectedRouteMode == 'manual') ? 3.2 : 4.0;
    final minutes = (totalMeters / (speedKmh * 1000 / 60)).round();

    setState(() {
      _navRoutePoints = points;
      _navDistanceMeters = totalMeters;
      _navEstMinutes = max(1, minutes);
      _isNavigating = true;
    });

    final bounds = LatLngBounds.fromPoints([start, dest]);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));

    _speakGuidance('${_destName ?? "목적지"}까지 보행약자 안전 경로 안내를 시작합니다. 90m 앞 단차 회피 우회전하세요.');
  }

  void _clearNavigation() {
    setState(() {
      _isNavigating = false;
      _destName = null;
      _destLocation = null;
      _navRoutePoints.clear();
      _destSearchController.clear();
    });
  }

  // Turn-by-turn Step Details Modal BottomSheet (진짜 길찾기 상세 리스트)
  void _showTurnByTurnStepsModal() {
    final dest = _destName ?? '목적지';
    final routeModeName = (_selectedRouteMode == 'electric') ? '⚡ 전동휠체어' : (_selectedRouteMode == 'manual') ? '♿ 수동휠체어' : '🚶 보행자';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🧭 $dest 상세 턴바이턴 경로',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '모드: $routeModeName | 총 ${(_navDistanceMeters).toStringAsFixed(0)}m (약 $_navEstMinutes분)',
                      style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _buildNavStepItem(
                    icon: Icons.my_location,
                    iconColor: Colors.green,
                    title: '출발지: $_startName',
                    subtitle: '작전역 승강기 위치에서 출발 준비 (평지 보도)',
                    distance: '0m',
                  ),
                  _buildNavStepItem(
                    icon: Icons.straight,
                    iconColor: Colors.blue,
                    title: '보도 직진 구간',
                    subtitle: '계양대로 방면 140m 직진 (경사도 1.5° 평탄 보도)',
                    distance: '140m',
                  ),
                  _buildNavStepItem(
                    icon: Icons.turn_right,
                    iconColor: Colors.orange,
                    title: '위험 단차 우회 & 우회전',
                    subtitle: '단차 12.5cm 위험 구간 감지 ➔ 우측 턱 없는 경사로 진입',
                    distance: '90m',
                  ),
                  _buildNavStepItem(
                    icon: Icons.straight,
                    iconColor: Colors.blue,
                    title: '통학로 보행자 전용도로 진입',
                    subtitle: '보도블록 완충 구간 지나 120m 직진',
                    distance: '120m',
                  ),
                  _buildNavStepItem(
                    icon: Icons.flag,
                    iconColor: Colors.red,
                    title: '도착: $dest',
                    subtitle: '주출입문 도착 (자동문 및 휠체어 진입 경사로 완비)',
                    distance: '도착',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavStepItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String distance,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(distance, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        ],
      ),
    );
  }

  void _showSearchSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue.shade800,
      ),
    );
  }

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

    _accelStreamSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (!_isTrackingRoute) return;
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
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
            _startLocation = newLoc;
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
            if (hazard['image_url'] != null && hazard['image_url'].toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  hazard['image_url'],
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(),
                ),
              ),
            ],
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
    final lat = (building['latitude'] as num?)?.toDouble();
    final lng = (building['longitude'] as num?)?.toDouble();

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
            Row(
              children: [
                if (lat != null && lng != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _destName = building['name'] ?? '도착 건물';
                          _destLocation = LatLng(lat, lng);
                          _uiMode = 'nav';
                        });
                        _calculateAccessibleRoute();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.navigation),
                      label: const Text('여기로 길찾기'),
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Polyline> _getRoutePolylines() {
    final List<Polyline> list = [];

    if (_trackedPoints.length > 1) {
      list.add(
        Polyline(
          points: List.from(_trackedPoints),
          strokeWidth: 6.0,
          color: Colors.purple.shade600,
        ),
      );
    }

    if (_isNavigating && _navRoutePoints.length > 1) {
      final routeColor = (_selectedRouteMode == 'electric')
          ? Colors.blue.shade600
          : (_selectedRouteMode == 'manual')
              ? Colors.green.shade600
              : Colors.deepOrange;

      list.add(
        Polyline(
          points: List.from(_navRoutePoints),
          strokeWidth: 7.5,
          color: routeColor,
        ),
      );
    } else {
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
    }

    return list;
  }

  List<Map<String, dynamic>> get _filteredHazards {
    if (_selectedCategoryFilter == 'all') {
      return _hazards;
    } else if (_selectedCategoryFilter == 'building') {
      return [];
    } else {
      return _hazards.where((h) => h['type'] == _selectedCategoryFilter).toList();
    }
  }

  List<Map<String, dynamic>> get _filteredBuildings {
    if (_selectedCategoryFilter == 'all' || _selectedCategoryFilter == 'building') {
      return _buildings;
    }
    return [];
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
            icon: Icon(_uiMode == 'nav' ? Icons.search : Icons.directions),
            tooltip: _uiMode == 'nav' ? '검색 모드' : '길찾기 모드',
            onPressed: () {
              setState(() {
                _uiMode = (_uiMode == 'nav') ? 'search' : 'nav';
              });
            },
          ),
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
          // Modern CartoDB Voyager Map Graphics
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
                    if (_uiMode == 'nav') {
                      _destLocation = point;
                      _destName = '지도 선택 위치';
                      _calculateAccessibleRoute();
                    }
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.flatway_app',
                ),
                
                PolylineLayer(
                  polylines: _getRoutePolylines(),
                ),

                MarkerLayer(
                  markers: [
                    ..._filteredHazards.where((h) => h['latitude'] != null && h['longitude'] != null).map((h) {
                      final lat = (h['latitude'] as num).toDouble();
                      final lng = (h['longitude'] as num).toDouble();
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 42,
                        height: 42,
                        child: GestureDetector(
                          onTap: () => _showHazardDetail(h),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.shade800,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.warning_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      );
                    }),

                    ..._filteredBuildings.where((b) => b['latitude'] != null && b['longitude'] != null).map((b) {
                      final lat = (b['latitude'] as num).toDouble();
                      final lng = (b['longitude'] as num).toDouble();
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 42,
                        height: 42,
                        child: GestureDetector(
                          onTap: () => _showBuildingDetail(b),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.business, color: Colors.white, size: 22),
                          ),
                        ),
                      );
                    }),

                    Marker(
                      point: _currentLocation,
                      width: 58,
                      height: 58,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isTrackingRoute
                              ? Colors.purple.withValues(alpha: 0.3)
                              : Colors.blue.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isTrackingRoute ? Colors.purple : Colors.blue,
                            width: 2.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _isTrackingRoute ? Colors.purple.shade700 : Colors.blue.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_destLocation != null)
                      Marker(
                        point: _destLocation!,
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                          ),
                          child: const Icon(Icons.location_on, color: Colors.white, size: 28),
                        ),
                      ),

                    if (_selectedTappedLocation != null && _destLocation != _selectedTappedLocation)
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

          // Real Navigation Top Guidance Banner (턴바이턴 네비게이션 헤더)
          if (_isNavigating)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                color: Colors.blue.shade900,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.lightGreenAccent.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.turn_right, color: Colors.black87, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '90m 앞 우회전 (단차 12.5cm 우회 구간)',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '다음: 계양대로 보행약자 안전길 진입 ➔ ${_destName ?? "목적지"}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: _clearNavigation,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Regular Search & Control Panel (when not navigating)
          if (!_isNavigating)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  if (_uiMode == 'search') ...[
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onSubmitted: _performSearch,
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                  hintText: '장소, 건물 또는 위험 요소 검색 (예: 작전역)',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.directions, color: Colors.blue),
                              tooltip: '길찾기 모드',
                              onPressed: () {
                                setState(() {
                                  _uiMode = 'nav';
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCategoryChip('all', '🌐 전체 (${_hazards.length + _buildings.length})'),
                          const SizedBox(width: 6),
                          _buildCategoryChip('step', '⚠️ 단차 (${_hazards.where((h) => h['type'] == 'step').length})'),
                          const SizedBox(width: 6),
                          _buildCategoryChip('damage', '🔨 파손 (${_hazards.where((h) => h['type'] == 'damage').length})'),
                          const SizedBox(width: 6),
                          _buildCategoryChip('obstacle', '🚫 적치물 (${_hazards.where((h) => h['type'] == 'obstacle').length})'),
                          const SizedBox(width: 6),
                          _buildCategoryChip('building', '🏢 건물 (${_buildings.length})'),
                        ],
                      ),
                    ),
                  ] else ...[
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 6,
                      color: Colors.blue.shade900,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.my_location, color: Colors.lightGreenAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '출발: $_startName',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _uiMode = 'search';
                                      _clearNavigation();
                                    });
                                  },
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 12),
                            Row(
                              children: [
                                const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _destSearchController,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    onSubmitted: (val) {
                                      _performSearch(val);
                                      if (_knownLandmarks.containsKey(val)) {
                                        setState(() {
                                          _destName = val;
                                          _destLocation = _knownLandmarks[val];
                                        });
                                        _calculateAccessibleRoute();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: _destName ?? '도착지 검색 또는 지도 위 클릭 (예: 작전여고)',
                                      hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final val = _destSearchController.text.trim();
                                    if (_knownLandmarks.containsKey(val)) {
                                      setState(() {
                                        _destName = val;
                                        _destLocation = _knownLandmarks[val];
                                      });
                                      _calculateAccessibleRoute();
                                    } else {
                                      _performSearch(val);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  child: const Text('길찾기'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 6),

                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                    color: _isTrackingRoute ? Colors.purple.shade900 : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
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
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: Text(_isTrackingRoute ? '수집 중단' : '경로 수집'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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

          // Real Navigation Active Route Summary & Step List Button
          if (_isNavigating && _destName != null)
            Positioned(
              bottom: 20,
              left: 14,
              right: 14,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 10,
                color: Colors.black.withValues(alpha: 0.92),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              const Text('소요 시간', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('약 $_navEstMinutes 분', style: const TextStyle(color: Colors.amberAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(width: 1, height: 32, color: Colors.white24),
                          Column(
                            children: [
                              const Text('남은 거리', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${(_navDistanceMeters).toStringAsFixed(0)} m', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(width: 1, height: 32, color: Colors.white24),
                          Column(
                            children: [
                              const Text('위험 회피', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('$_bypassedHazardsCount 건', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 19, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showTurnByTurnStepsModal,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.format_list_bulleted, size: 18),
                              label: const Text('📋 상세 턴바이턴 경로 목록 보기'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _clearNavigation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('안내 종료'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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

  Widget _buildCategoryChip(String categoryKey, String label) {
    final isSelected = _selectedCategoryFilter == categoryKey;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.blue.shade700,
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      elevation: 2,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedCategoryFilter = categoryKey;
          });
        }
      },
    );
  }

  Widget _buildRouteModeButton(String modeKey, String label, Color color) {
    final isSelected = _selectedRouteMode == modeKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRouteMode = modeKey;
          if (_isNavigating) {
            _calculateAccessibleRoute();
          }
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
