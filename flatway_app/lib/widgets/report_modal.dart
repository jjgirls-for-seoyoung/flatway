import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_service.dart';

class ReportModal extends StatefulWidget {
  final LatLng initialLocation;
  final VoidCallback onReportSubmitted;

  const ReportModal({
    super.key,
    required this.initialLocation,
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

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final newHazard = {
      'type': _selectedType,
      'latitude': widget.initialLocation.latitude,
      'longitude': widget.initialLocation.longitude,
      'step_height_cm': _selectedType == 'step' ? _stepHeight : null,
      'severity': _selectedSeverity,
      'description': _descriptionController.text.trim(),
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
              
              // Location Info
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '제보 좌표: ${widget.initialLocation.latitude.toStringAsFixed(5)}, ${widget.initialLocation.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
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

              // Step Height Slider (Only for step type)
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
                  label: Text(_isSubmitting ? '제보 등록 중...' : '제보 등록하기'),
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
