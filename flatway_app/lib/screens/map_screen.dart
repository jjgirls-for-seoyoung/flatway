import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
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
  bool _isLocating = true;
  String _locationStatus = '현재 위치 찾는 중...';
  double? _accuracy;

  List<Map<String, dynamic>> _hazards = [];
  List<Map<String, dynamic>> _buildings = [];
  bool _isLoadingData = true;

  // Selected route mode: 'pedestrian' | 'electric' | 'manual'
  String _selectedRouteMode = 'pedestrian';

  // Selected map tapped location for reporting
  LatLng? _selectedTappedLocation;

  @override
  void initState() {
    super.initState();
    _initDataAndLocation();
  }

  Future<void> _initDataAndLocation() async {
    await Future.wait([
      _fetchCurrentLocation(),
      _loadSupabaseData(),
    ]);
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locationStatus = 'GPS 위치 정보 요청 중...';
    });

    final Position? position = await LocationService.getCurrentPosition();

    if (mounted) {
      if (position != null) {
        final newLoc = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentLocation = newLoc;
          _accuracy = position.accuracy;
          _isLocating = false;
          _locationStatus = '현재 위치 수집 완료 (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})';
        });
        _mapController.move(newLoc, 17.0);
      } else {
        setState(() {
          _isLocating = false;
          _locationStatus = '위치 권한 미승인 또는 GPS 비활성화 (기본 위치 표시)';
        });
      }
    }
  }

  Future<void> _loadSupabaseData() async {
    setState(() {
      _isLoadingData = true;
    });

    final hazards = await SupabaseService.fetchHazards();
    final buildings = await SupabaseService.fetchBuildings();

    if (mounted) {
      setState(() {
        _hazards = hazards;
        _buildings = buildings;
        _isLoadingData = false;
      });
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
    // Jakjeon station -> Jakjeon Girls High School route points
    if (_selectedRouteMode == 'electric') {
      return [
        Polyline(
          points: const [
            LatLng(37.5346, 126.7225), // Jakjeon station
            LatLng(37.5350, 126.7230),
            LatLng(37.5360, 126.7240),
            LatLng(37.5375, 126.7248),
            LatLng(37.5385, 126.7240), // Jakjeon Girls HS
          ],
          strokeWidth: 5.0,
          color: Colors.blue.shade600,
        ),
      ];
    } else if (_selectedRouteMode == 'manual') {
      return [
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
      ];
    } else {
      // Pedestrian default
      return [
        Polyline(
          points: const [
            LatLng(37.5346, 126.7225),
            LatLng(37.5360, 126.7235),
            LatLng(37.5385, 126.7240),
          ],
          strokeWidth: 4.0,
          color: Colors.orange.shade600,
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlatWay - 보행 안전 안내 지도'),
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
          // FlutterMap Tile, Polyline & Marker Layers (Wrapped in Positioned.fill so map occupies full screen)
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 16.5,
                minZoom: 10.0,
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
                
                // Safe Route Polyline Layer
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
                        color: Colors.blue.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
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

          // Top Control Panel: Route Mode Selector & GPS status
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // GPS Status Card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: (_isLocating || _isLoadingData)
                              ? const CircularProgressIndicator(strokeWidth: 2.5)
                              : const Icon(Icons.my_location, color: Colors.blue, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _locationStatus,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_accuracy != null)
                          Text(
                            '오차 ±${_accuracy!.toStringAsFixed(0)}m',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
