import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_service.dart';

class ReportModal extends StatefulWidget {
  final LatLng initialLocation;
  final String? placeName;
  final VoidCallback onReportSubmitted;

  const ReportModal({
    super.key,
    required this.initialLocation,
    this.placeName,
    required this.onReportSubmitted,
  });

  @override
  State<ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<ReportModal> {
  final _formKey = GlobalKey<FormState>();
  
  String _selectedType = 'step'; // 'step', 'damage', 'obstacle', 'slope'
  String _selectedSeverity = 'medium'; // 'high', 'medium', 'low'
  double _stepHeight = 4.0;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  // Address & Reverse Geocoding State
  String _resolvedAddress = '주소 정보 확인 중...';
  bool _isLoadingAddress = true;

  @override
  void initState() {
    super.initState();
    _fetchReverseGeocode();
  }

  Future<void> _fetchReverseGeocode() async {
    try {
      final lat = widget.initialLocation.latitude;
      final lng = widget.initialLocation.longitude;

      // Try VWorld reverse geocoding API
      final vworldUrl = Uri.parse(
        'https://api.vworld.kr/req/address?service=address&request=getAddress&version=2.0&crs=epsg:4326&point=$lng,$lat&type=BOTH&zipcode=true&simple=false&key=CEB52025-E0A2-3031-893C-E05F83216892',
      );
      final response = await http.get(vworldUrl).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['response'] != null && data['response']['status'] == 'OK') {
          final result = data['response']['result'][0];
          final text = result['text'];
          if (text != null && text.toString().isNotEmpty) {
            if (mounted) {
              setState(() {
                _resolvedAddress = text.toString();
                _isLoadingAddress = false;
              });
            }
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback to OSM Nominatim
    try {
      final lat = widget.initialLocation.latitude;
      final lng = widget.initialLocation.longitude;
      final osmUrl = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&accept-language=ko');
      final response = await http.get(osmUrl, headers: {'User-Agent': 'FlatWayApp/1.0'}).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final displayName = data['display_name'];
        if (displayName != null && displayName.toString().isNotEmpty) {
          final parts = displayName.toString().split(',');
          final shortAddr = parts.take(min(3, parts.length)).join(' ').trim();
          if (mounted) {
            setState(() {
              _resolvedAddress = shortAddr;
              _isLoadingAddress = false;
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _resolvedAddress = '인천광역시 계양구 보행로';
        _isLoadingAddress = false;
      });
    }
  }

  // Photo Attachment State
  XFile? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  final Map<String, String> _typeLabels = {
    'step': '보행 단차 (턱)',
    'damage': '노면 파손 및 요철',
    'obstacle': '불법 주차/적치물',
    'slope': '보도 급경사',
  };

  final Map<String, String> _severityLabels = {
    'high': '상 (휠체어 통행 불가)',
    'medium': '중 (통행 불편/위험)',
    'low': '하 (경미한 불편)',
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = picked;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    String? imageUrl;
    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      imageUrl = await SupabaseService.uploadHazardPhotoBytes(bytes);
    }

    final newHazard = {
      'type': _selectedType,
      'latitude': widget.initialLocation.latitude,
      'longitude': widget.initialLocation.longitude,
      'step_height_cm': _selectedType == 'step' ? _stepHeight : null,
      'severity': _selectedSeverity,
      'description': _descriptionController.text.trim(),
      'image_url': imageUrl,
      'is_verified': false,
      'reported_at': DateTime.now().toUtc().toIso8601String(),
    };

    final success = await SupabaseService.insertHazard(newHazard);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('단차/노면 파손 제보가 Supabase DB에 성공적으로 등록되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReportSubmitted();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('제보 등록에 실패했습니다. 다시 시도해 주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_location_alt, color: Colors.orange, size: 28),
                      SizedBox(width: 8),
                      Text(
                        '보행 장애 요소 제보하기',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              
              // Location Info (Show Nearby Landmark/Building Name & Street Address)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDFDFDF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 20, color: Color(0xFF047857)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.placeName ?? '지도 선택 제보 위치',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111111),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.map_rounded, size: 16, color: Color(0xFF777777)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _isLoadingAddress
                              ? const Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF047857)),
                                    ),
                                    SizedBox(width: 8),
                                    Text('주소 정보를 변환하는 중...', style: TextStyle(fontSize: 12, color: Color(0xFF949494))),
                                  ],
                                )
                              : Text(
                                  _resolvedAddress,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF555555), fontWeight: FontWeight.w500),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Hazard Type Selector
              const Text('위험 유형', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _typeLabels.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedType = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Step Height Slider
              if (_selectedType == 'step') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('측정 단차 높이', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${_stepHeight.toStringAsFixed(1)} cm',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
                Slider(
                  value: _stepHeight,
                  min: 1.0,
                  max: 15.0,
                  divisions: 28,
                  label: '${_stepHeight.toStringAsFixed(1)} cm',
                  activeColor: Colors.orange,
                  onChanged: (val) {
                    setState(() {
                      _stepHeight = val;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Severity Selector
              const Text('위험도', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedSeverity,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _severityLabels.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSeverity = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Photo Attachment Section
              const Text('현장 사진 첨부', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('카메라 촬영'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('갤러리 선택'),
                  ),
                ],
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 10),
                Stack(
                  children: [
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                            : Image.network(_selectedImage!.path, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImage = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Description Text Field
              const Text('상세 설명 및 특이사항', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '예: 보행로 턱이 높아 수동 휠체어 진입이 어려움',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return '상세 설명을 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSubmitting ? '제보 등록 및 사진 업로드 중...' : '제보 등록하기'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
