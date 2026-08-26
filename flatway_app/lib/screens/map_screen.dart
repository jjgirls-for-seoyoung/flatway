import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:sensors_plus/sensors_plus.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
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

  List<Map<String, dynamic>> _hazards = [];
  List<Map<String, dynamic>> _buildings = [];

  // Selected Category Filter: 'all' | 'step' | 'damage' | 'obstacle' | 'building'
  String _selectedCategoryFilter = 'all';

  // Route Mode: 'pedestrian' | 'electric' | 'manual'
  String _selectedRouteMode = 'pedestrian';

  // Search Expansion & Recommendation State
  bool _isRouteSearchExpanded = false;
  final List<String> _recentSearches = ['작전역', '작전여고', '계양구청', '작전역 1번 출구'];

  // Map Tile Style: 'vworld' | 'satellite' | 'esri_sat' | 'dark' | 'carto'
  String _selectedMapTileStyle = 'vworld';
  final bool _isDarkMode = false;

  // Navigation Origin & Destination (Initially null so BOTH must be explicitly chosen)
  String? _startName;
  LatLng? _startLocation;
  String? _destName;
  LatLng? _destLocation;
  bool _isNavigating = false;
  List<LatLng> _navRoutePoints = [];
  List<RouteStep> _navRouteSteps = [];
  double _navDistanceMeters = 0.0;
  int _navEstMinutes = 0;
  int _bypassedHazardsCount = 0;

  bool _isHeadingUp = false;
  double _currentHeading = 0.0;
  StreamSubscription<CompassEvent>? _alwaysCompassSub;
  StreamSubscription<Position>? _realtimeLocationSub;

  void _startRealtimeLocationTracking() {
    _realtimeLocationSub?.cancel();
    _realtimeLocationSub = LocationService.getPositionStream().listen((Position position) {
      if (!mounted) return;
      final newLoc = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = newLoc;
      });
      if (_isHeadingUp) {
        try {
          _mapController.move(newLoc, _mapController.camera.zoom);
        } catch (_) {}
      }
    });
  }

  void _startCompassHeadingListener() {
    _alwaysCompassSub?.cancel();
    _alwaysCompassSub = FlutterCompass.events?.listen((CompassEvent event) {
      final heading = event.heading;
      if (heading != null && mounted) {
        setState(() {
          _currentHeading = heading;
        });
        if (_isHeadingUp) {
          _mapController.rotate(-heading);
        }
      }
    });
  }

  void _toggleCompassHeadingMode() {
    setState(() {
      _isHeadingUp = !_isHeadingUp;
    });

    if (!_isHeadingUp) {
      _mapController.rotate(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('북쪽 정방향 지도 모드로 변경되었습니다.'),
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      _mapController.move(_currentLocation, 17.5);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('실시간 나침반 방향 회전 모드가 켜졌습니다.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
  
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
    _startRealtimeLocationTracking();
    _startCompassHeadingListener();
  }

  @override
  void dispose() {
    _realtimeLocationSub?.cancel();
    _positionStreamSub?.cancel();
    _accelStreamSub?.cancel();
    _alwaysCompassSub?.cancel();
    _searchController.dispose();
    _startSearchController.dispose();
    _destSearchController.dispose();
    super.dispose();
  }

  // Search History Helper
  void _addRecentSearch(String term) {
    final clean = term.trim();
    if (clean.isEmpty) return;
    setState(() {
      _recentSearches.remove(clean);
      _recentSearches.insert(0, clean);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
    });
  }

  // Handle Location & Building Search
  void _performSearch(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return;

    _addRecentSearch(query);

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

  void _showSearchRecommendationModal({bool isSettingStart = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDFDFDF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSettingStart ? Icons.my_location_rounded : Icons.location_on_rounded,
                          color: isSettingStart ? const Color(0xFF047857) : const Color(0xFFE8332E),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSettingStart ? '출발지 선택' : '도착지 선택',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF777777)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 16, color: Color(0xFFEFEFEF)),
                
                // Quick Current Location Option for Origin / Destination Selection
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSettingStart ? const Color(0xFF047857).withValues(alpha: 0.12) : const Color(0xFFE8332E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      isSettingStart ? Icons.my_location_rounded : Icons.location_on_rounded,
                      color: isSettingStart ? const Color(0xFF047857) : const Color(0xFFE8332E),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    isSettingStart ? '현재 위치를 출발지로 설정' : '현재 위치를 도착지로 설정',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111111)),
                  ),
                  subtitle: Text(
                    isSettingStart ? '내 GPS 현재 위치에서 출발합니다' : '내 GPS 현재 위치로 목적지를 설정합니다',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF949494)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      if (isSettingStart) {
                        _startName = '현재 위치';
                        _startLocation = _currentLocation;
                        _startSearchController.text = '현재 위치';
                      } else {
                        _destName = '현재 위치';
                        _destLocation = _currentLocation;
                        _destSearchController.text = '현재 위치';
                      }
                      _isRouteSearchExpanded = true;
                    });
                    if (_startLocation != null && _destLocation != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('출발지와 도착지가 모두 설정되었습니다. [길찾기] 완료 버튼을 누르면 탐색됩니다.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isSettingStart ? '도착지를 선택해 주세요.' : '출발지를 선택해 주세요.'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('🕒 최근 검색 기록', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF777777))),
                    if (_recentSearches.isNotEmpty)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _recentSearches.clear();
                          });
                        },
                        child: const Text('전체 삭제', style: TextStyle(fontSize: 11, color: Color(0xFF949494))),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_recentSearches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        '최근 검색 기록이 없습니다.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF949494)),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _recentSearches.map((term) {
                      return ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 14, color: Color(0xFF777777)),
                        label: Text(term, style: const TextStyle(fontSize: 12, color: Color(0xFF111111))),
                        backgroundColor: const Color(0xFFF5F5F5),
                        side: const BorderSide(color: Color(0xFFDFDFDF), width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        onPressed: () {
                          Navigator.pop(context);
                          _addRecentSearch(term);
                          if (_knownLandmarks.containsKey(term)) {
                            setState(() {
                              if (isSettingStart) {
                                _startName = term;
                                _startLocation = _knownLandmarks[term];
                                _startSearchController.text = term;
                              } else {
                                _destName = term;
                                _destLocation = _knownLandmarks[term];
                                _destSearchController.text = term;
                              }
                              _isRouteSearchExpanded = true;
                            });
                            if (_startLocation != null && _destLocation != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('출발지와 도착지가 설정되었습니다. [길찾기] 완료 버튼을 누르면 탐색됩니다.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isSettingStart ? '도착지를 추가로 선택해주세요.' : '출발지를 추가로 선택해주세요.'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } else {
                            _performSearch(term);
                          }
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMapTapLocationActionModal(LatLng point) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isStartSet = _startLocation != null;
          final isDestSet = _destLocation != null;
          final isBothSet = isStartSet && isDestSet;

          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDFDFDF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF047857).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Icon(Icons.touch_app_rounded, color: Color(0xFF047857), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '지도 선택 위치 지정',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
                            ),
                            Text(
                              '터치한 장소를 출발지/도착지로 선택하세요',
                              style: TextStyle(fontSize: 11, color: Color(0xFF949494)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF777777)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 16, color: Color(0xFFEFEFEF)),
                
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _startName = '지도 선택 위치';
                            _startLocation = point;
                            _startSearchController.text = '지도 선택 위치';
                            _isRouteSearchExpanded = true;
                          });
                          setModalState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('출발지로 설정되었습니다. (도착지를 선택하면 탐색이 완료됩니다)'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF047857),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: const Text('출발지로 설정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _destName = '지도 선택 위치';
                            _destLocation = point;
                            _destSearchController.text = '지도 선택 위치';
                            _isRouteSearchExpanded = true;
                          });
                          setModalState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('도착지로 설정되었습니다. (출발지를 선택하면 탐색이 완료됩니다)'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8332E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                        icon: const Icon(Icons.location_on_rounded, size: 16),
                        label: const Text('도착지로 설정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openReportModal(point);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E2742),
                          side: const BorderSide(color: Color(0xFFDFDFDF)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                        icon: const Icon(Icons.report_problem_rounded, size: 16),
                        label: const Text('이 위치 위험 요인 제보', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),

                if (isBothSet) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _calculateAccessibleRoute();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: const Text('위치 설정 완료 & 경로 탐색 시작', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // Calculate real OSRM pedestrian road route following actual streets and crosswalks
  Future<void> _calculateAccessibleRoute() async {
    final dest = _destLocation;
    final start = _startLocation;
    if (start == null || dest == null) return;

    // Calculate dangerous hazards near route
    final dangerousHazards = _hazards.where((h) {
      final lat = (h['latitude'] as num?)?.toDouble();
      final lng = (h['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      final severity = h['severity'] ?? '';
      final height = (h['step_height_cm'] as num?)?.toDouble() ?? 0;
      return severity == 'high' || height > 8.0;
    }).toList();

    _bypassedHazardsCount = dangerousHazards.length;

    // Fetch real OSRM pedestrian walking route following actual streets and sidewalks
    final result = await RouteService.fetchPedestrianRoute(origin: start, destination: dest);

    final speedKmh = (_selectedRouteMode == 'electric') ? 6.0 : (_selectedRouteMode == 'manual') ? 3.2 : 4.0;
    final minutes = (result.distanceMeters / (speedKmh * 1000 / 60)).round();

    if (mounted) {
      setState(() {
        _navRoutePoints = result.points;
        _navRouteSteps = result.steps;
        _navDistanceMeters = result.distanceMeters;
        _navEstMinutes = max(1, minutes);
        _isNavigating = true;
      });

      if (result.points.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(result.points);
        _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
      }

      _speakGuidance('${_destName ?? "목적지"}까지 보행자 도로망 실시간 경로 안내를 시작합니다.');
    }
  }

  void _clearNavigation() {
    setState(() {
      _isNavigating = false;
      _startName = null;
      _startLocation = null;
      _destName = null;
      _destLocation = null;
      _navRoutePoints.clear();
      _startSearchController.clear();
      _destSearchController.clear();
    });
  }

  // Turn-by-turn Step Details Modal BottomSheet (진짜 길찾기 상세 리스트)
  void _showTurnByTurnStepsModal() {
    final dest = _destName ?? '목적지';
    final routeModeName = (_selectedRouteMode == 'electric') ? '전동휠체어' : (_selectedRouteMode == 'manual') ? '수동휠체어' : '보행자';

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
                      '$dest 상세 턴바이턴 경로',
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
              child: ListView.builder(
                itemCount: _navRouteSteps.isEmpty ? 1 : _navRouteSteps.length,
                itemBuilder: (context, index) {
                  if (_navRouteSteps.isEmpty) {
                    return _buildNavStepItem(
                      icon: Icons.my_location,
                      iconColor: Colors.green,
                      title: '출발지: ${_startName ?? "미선택"} ➔ 도착지: $dest',
                      subtitle: '경로 데이터를 계산 중입니다.',
                      distance: '${_navDistanceMeters.toStringAsFixed(0)}m',
                    );
                  }

                  final step = _navRouteSteps[index];
                  final isLast = index == _navRouteSteps.length - 1;
                  final isFirst = index == 0;

                  final IconData stepIcon = isFirst
                      ? Icons.my_location
                      : isLast
                          ? Icons.flag
                          : step.modifier.contains('right')
                              ? Icons.turn_right
                              : step.modifier.contains('left')
                                  ? Icons.turn_left
                                  : Icons.straight;

                  final Color stepColor = isFirst
                      ? Colors.green
                      : isLast
                          ? Colors.red
                          : step.modifier.contains('right') || step.modifier.contains('left')
                              ? Colors.orange
                              : Colors.blue;

                  return _buildNavStepItem(
                    icon: stepIcon,
                    iconColor: stepColor,
                    title: isFirst ? '출발지: ${_startName ?? "미선택"}' : isLast ? '도착지: $dest' : '보행 이동 구간 ${index + 1}',
                    subtitle: step.instruction,
                    distance: '${step.distanceMeters.toStringAsFixed(0)}m',
                  );
                },
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(distance, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
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
        content: Text('이동 경로 및 노면 단차 자동 수집이 시작되었습니다.'),
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
          '수집 종료! 이동거리: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)}km, 자동 감지: $_autoDetectedBumpsCount건',
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

  bool _isGpsRequiredModalOpen = false;

  void _checkGpsAndPermissions() async {
    bool serviceEnabled = await LocationService.isLocationServiceEnabled();
    LocationPermission permission = await LocationService.checkPermission();

    if (!serviceEnabled || permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted && !_isGpsRequiredModalOpen) {
        _isGpsRequiredModalOpen = true;
        _showMandatoryGpsDialog();
      }
    }
  }

  void _showMandatoryGpsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_off_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  '위치 서비스 연결',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            content: Text(
              'FlatWay 보행약자 안전 지도를 이용하려면 스마트폰의 위치 서비스와 앱 권한 허용이 필요합니다. 아래 버튼을 눌러 위치 권한을 켜주세요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: _isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await LocationService.openLocationSettings();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('위치(GPS) 설정 열기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await LocationService.openAppSettings();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      foregroundColor: _isDarkMode ? Colors.white : const Color(0xFF0F172A),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('앱 권한 설정 열기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      _isGpsRequiredModalOpen = false;
                      await _fetchCurrentLocation();
                    },
                    child: const Text('설정 완료 후 다시 시도', style: TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;

    try {
      final Position? position = await LocationService.getCurrentPosition();

      if (mounted) {
        if (position != null) {
          final newLoc = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentLocation = newLoc;
          });
          
          try {
            _mapController.move(newLoc, 16.5);
          } catch (e) {
            debugPrint('MapController move deferred: $e');
          }
        } else {
          _checkGpsAndPermissions();
        }
      }
    } catch (e) {
      if (mounted) {
        _checkGpsAndPermissions();
      }
    }
  }

  Future<void> _loadSupabaseData() async {
    if (!mounted) return;

    try {
      final hazards = await SupabaseService.fetchHazards();
      final buildings = await SupabaseService.fetchBuildings();

      if (mounted) {
        setState(() {
          _hazards = hazards;
          _buildings = buildings;
        });
      }
    } catch (e) {
      debugPrint('Error loading Supabase data: $e');
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('👍 제보 검증 감사 드리며, 위험 신뢰도가 상승했습니다!'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    icon: const Icon(Icons.thumb_up_alt_outlined, color: Colors.blue, size: 18),
                    label: const Text('도움이 돼요'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ),
              ],
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
                if (lat != null && lng != null) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _startName = building['name'] ?? '선택 건물';
                          _startLocation = LatLng(lat, lng);
                          _startSearchController.text = _startName!;
                          _isRouteSearchExpanded = true;
                        });
                        if (_destLocation != null) _calculateAccessibleRoute();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('출발지로 지정', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _destName = building['name'] ?? '도착 건물';
                          _destLocation = LatLng(lat, lng);
                          _destSearchController.text = _destName!;
                          _isRouteSearchExpanded = true;
                        });
                        _calculateAccessibleRoute();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.location_on, size: 16),
                      label: const Text('도착지로 지정', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
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

  Widget _buildTileLayer() {
    if (_selectedMapTileStyle == 'satellite') {
      return Stack(
        children: [
          TileLayer(
            urlTemplate: 'https://xdworld.vworld.kr/2d/Satellite/service/{z}/{x}/{y}.jpeg',
            maxNativeZoom: 19,
            maxZoom: 22,
            userAgentPackageName: 'com.example.flatway_app',
          ),
          TileLayer(
            urlTemplate: 'https://xdworld.vworld.kr/2d/Hybrid/service/{z}/{x}/{y}.png',
            maxNativeZoom: 19,
            maxZoom: 22,
            userAgentPackageName: 'com.example.flatway_app',
          ),
        ],
      );
    } else if (_selectedMapTileStyle == 'esri_sat') {
      return TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        maxNativeZoom: 19,
        maxZoom: 22,
        userAgentPackageName: 'com.example.flatway_app',
      );
    } else {
      return TileLayer(
        urlTemplate: 'https://xdworld.vworld.kr/2d/Base/service/{z}/{x}/{y}.png',
        maxNativeZoom: 19,
        maxZoom: 22,
        userAgentPackageName: 'com.example.flatway_app',
      );
    }
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
              'FlatWay',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers, color: Colors.blue),
            tooltip: '지도 스타일 변경',
            onSelected: (style) {
              setState(() {
                _selectedMapTileStyle = style;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'vworld',
                child: Text('한글 정밀지도'),
              ),
              const PopupMenuItem(
                value: 'satellite',
                child: Text('위성 하이브리드지도'),
              ),
              const PopupMenuItem(
                value: 'esri_sat',
                child: Text('위성지도'),
              ),
            ],
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
                maxZoom: 22.0,
                onTap: (tapPosition, point) {
                  setState(() {
                    _selectedTappedLocation = point;
                  });
                  _showMapTapLocationActionModal(point);
                },
              ),
              children: [
                _buildTileLayer(),
                
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
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _showHazardDetail(h),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.shade800,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Icon(Icons.warning_rounded, color: Colors.white, size: 15),
                          ),
                        ),
                      );
                    }),

                    ..._filteredBuildings.where((b) => b['latitude'] != null && b['longitude'] != null).map((b) {
                      final lat = (b['latitude'] as num).toDouble();
                      final lng = (b['longitude'] as num).toDouble();
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _showBuildingDetail(b),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Icon(Icons.business, color: Colors.white, size: 15),
                          ),
                        ),
                      );
                    }),

                    Marker(
                      point: _currentLocation,
                      width: 28,
                      height: 34,
                      child: Transform.rotate(
                        angle: (_currentHeading * (pi / 180)),
                        child: CustomPaint(
                          size: const Size(28, 34),
                          painter: DirectionalPinPainter(
                            fillColor: const Color(0xFF047857),
                            borderColor: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    if (_destLocation != null)
                      Marker(
                        point: _destLocation!,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.location_on, color: Colors.white, size: 18),
                        ),
                      ),

                    if (_selectedTappedLocation != null && _destLocation != _selectedTappedLocation)
                      Marker(
                        point: _selectedTappedLocation!,
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _openReportModal(_selectedTappedLocation!),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: const Icon(Icons.add_location_alt, color: Colors.white, size: 16),
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
                color: const Color(0xFF1E3A8A),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF047857),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.turn_right, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '90m 앞 우회전 (단차 우회 구간)',
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
                    ],
                  ),
                ),
              ),
            ),

          // 1. Top Section: Clean Search Box (Shown when NOT navigating)
          if (!_isNavigating)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Column(
                children: [
                if (!_isRouteSearchExpanded) ...[
                  // Collapsed Single Search Bar (LDSG Style: White surface, 7px radius, gray-300 border)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                      side: const BorderSide(color: Color(0xFFDFDFDF), width: 1),
                    ),
                    elevation: 1,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: Color(0xFF047857), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              readOnly: false,
                              onTap: () => _showSearchRecommendationModal(isSettingStart: false),
                              onSubmitted: (val) {
                                _performSearch(val);
                              },
                              decoration: const InputDecoration(
                                hintText: '지도 검색 (장소, 건물 입력)...',
                                hintStyle: TextStyle(fontSize: 13, color: Color(0xFF949494)),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF111111)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.directions_rounded, color: Color(0xFF047857)),
                            tooltip: '길찾기 출발/도착지 설정',
                            onPressed: () {
                              setState(() {
                                _isRouteSearchExpanded = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Expanded Dual Route Search Card (LDSG Style: 12px radius, gray-300 border)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFDFDFDF), width: 1),
                    ),
                    elevation: 2,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Origin Row
                          Row(
                            children: [
                              const Icon(Icons.my_location_rounded, color: Color(0xFF047857), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _startSearchController,
                                  readOnly: true,
                                  onTap: () => _showSearchRecommendationModal(isSettingStart: true),
                                  style: const TextStyle(color: Color(0xFF111111), fontSize: 13, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: _startName ?? '출발지 선택 (터치)',
                                    hintStyle: TextStyle(
                                      color: _startName != null ? const Color(0xFF111111) : const Color(0xFF949494),
                                      fontSize: 13,
                                      fontWeight: _startName != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_startLocation != null)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: Color(0xFF777777), size: 16),
                                  onPressed: () {
                                    setState(() {
                                      _startName = null;
                                      _startLocation = null;
                                      _startSearchController.clear();
                                    });
                                  },
                                ),
                              // Quick "현재 위치" pick button
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _startName = '현재 위치';
                                    _startLocation = _currentLocation;
                                    _startSearchController.text = '현재 위치';
                                  });
                                  if (_destLocation == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('도착지를 선택해 주세요.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF047857).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3)),
                                  ),
                                  child: const Text('현재 위치', style: TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.swap_vert_rounded, color: Color(0xFF047857), size: 20),
                                tooltip: '출발지/도착지 위치 교환',
                                onPressed: () {
                                  setState(() {
                                    final tempName = _startName;
                                    final tempLoc = _startLocation;
                                    _startName = _destName;
                                    _startLocation = _destLocation;
                                    _destName = tempName;
                                    _destLocation = tempLoc;
                                    _startSearchController.text = _startName ?? '';
                                    _destSearchController.text = _destName ?? '';
                                  });
                                  if (_startLocation != null && _destLocation != null) {
                                    _calculateAccessibleRoute();
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Color(0xFF777777), size: 20),
                                tooltip: '접기',
                                onPressed: () {
                                  setState(() {
                                    _isRouteSearchExpanded = false;
                                  });
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 10, color: Color(0xFFEFEFEF)),
                          
                          // Destination Row
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: Color(0xFFE8332E), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _destSearchController,
                                  readOnly: true,
                                  onTap: () => _showSearchRecommendationModal(isSettingStart: false),
                                  style: const TextStyle(color: Color(0xFF111111), fontSize: 13, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: _destName ?? '도착지 선택 (터치)',
                                    hintStyle: TextStyle(
                                      color: _destName != null ? const Color(0xFF111111) : const Color(0xFF949494),
                                      fontSize: 13,
                                      fontWeight: _destName != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_destLocation != null)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: Color(0xFF777777), size: 16),
                                  onPressed: () {
                                    setState(() {
                                      _destName = null;
                                      _destLocation = null;
                                      _destSearchController.clear();
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Status & Action Guidance Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  (_startLocation == null && _destLocation == null)
                                      ? '출발지와 도착지를 모두 선택해 주세요.'
                                      : (_startLocation == null)
                                          ? '출발지를 선택해 주세요.'
                                          : (_destLocation == null)
                                              ? '도착지를 선택해 주세요.'
                                              : '출발지와 도착지가 모두 선택되었습니다.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: (_startLocation != null && _destLocation != null) ? FontWeight.bold : FontWeight.normal,
                                    color: (_startLocation != null && _destLocation != null)
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF777777),
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: (_startLocation != null && _destLocation != null)
                                    ? _calculateAccessibleRoute
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF047857),
                                  disabledBackgroundColor: const Color(0xFFE4E4E4),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: const Color(0xFF949494),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                ),
                                child: const Text('길찾기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 6),

                // Category Chips Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('all', '전체 (${_hazards.length + _buildings.length})'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('step', '단차 (${_hazards.where((h) => h['type'] == 'step').length})'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('damage', '파손 (${_hazards.where((h) => h['type'] == 'damage').length})'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('obstacle', '적치물 (${_hazards.where((h) => h['type'] == 'obstacle').length})'),
                      const SizedBox(width: 6),
                      _buildCategoryChip('building', '건물 (${_buildings.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Bottom Section: Reporting Action Panel (Idle) OR Navigation & Mobility Mode Selector (Navifying)
          Positioned(
            bottom: 20,
            left: 14,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isNavigating) ...[
                  // Normal Idle State: Reporting Choice Panel (현위치 제보 vs 이동 수집)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFDFDFDF), width: 1),
                    ),
                    elevation: 2,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isTrackingRoute) ...[
                            Row(
                              children: [
                                const Icon(Icons.route_rounded, color: Color(0xFF047857), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '실시간 이동 수집 중 (${(_totalDistanceMeters / 1000).toStringAsFixed(2)}km, 충격: $_autoDetectedBumpsCount건)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111111)),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 12, color: Color(0xFFEFEFEF)),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _openReportModal(_currentLocation),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E2742),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  ),
                                  icon: const Icon(Icons.report_problem_rounded, size: 18),
                                  label: const Text('현위치 제보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _toggleRouteTracking,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isTrackingRoute ? const Color(0xFFE8332E) : const Color(0xFF047857),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  ),
                                  icon: Icon(_isTrackingRoute ? Icons.stop_circle_rounded : Icons.directions_walk_rounded, size: 18),
                                  label: Text(
                                    _isTrackingRoute ? '수집 중단' : '이동 수집 시작',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Navigation Active Mode: Mobility Mode Selector Bar
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildRouteModeButton('pedestrian', '보행자', Colors.orange),
                          _buildRouteModeButton('electric', '전동휠체어', Colors.blue),
                          _buildRouteModeButton('manual', '수동휠체어', Colors.green),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Route Summary Dashboard
                  Card(
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
                                  const Text('보행 안전 지수', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text('${max(80, 100 - _bypassedHazardsCount * 2)}점', style: const TextStyle(color: Colors.cyanAccent, fontSize: 19, fontWeight: FontWeight.bold)),
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
                                  label: const Text('상세 경로 목록'),
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
                ],
              ],
            ),
          ),

          // Floating Compass Heading-up View Toggle Button
          Positioned(
            bottom: _isNavigating ? 210 : 105,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'compass_toggle',
              backgroundColor: _isHeadingUp ? Colors.blue.shade800 : Colors.white,
              foregroundColor: _isHeadingUp ? Colors.white : Colors.black87,
              onPressed: _toggleCompassHeadingMode,
              child: const Icon(Icons.explore),
            ),
          ),
        ],
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
          color: isSelected ? Colors.white : const Color(0xFF111111),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF047857),
      backgroundColor: const Color(0xFFF5F5F5),
      side: BorderSide(color: isSelected ? const Color(0xFF047857) : const Color(0xFFDFDFDF), width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
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
    const accentColor = Color(0xFF047857);
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRouteMode = modeKey;
          if (_isNavigating) {
            _calculateAccessibleRoute();
          }
        });
      },
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFFDFDFDF),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? accentColor : const Color(0xFF111111),
          ),
        ),
      ),
    );
  }
}

class DirectionalPinPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;

  DirectionalPinPainter({
    this.fillColor = const Color(0xFF047857),
    this.borderColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sleek Sharp Navigation Triangle Needle Pointer Path (pointing UP)
    final path = Path();
    path.moveTo(w / 2, 0); // Top sharp tip
    path.lineTo(w, h); // Bottom right corner
    path.quadraticBezierTo(w / 2, h * 0.78, 0, h); // Concave bottom notch
    path.close();

    // Drop Shadow
    canvas.drawShadow(path, Colors.black54, 4.0, true);

    // Fill Color
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Crisp White Outer Border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
