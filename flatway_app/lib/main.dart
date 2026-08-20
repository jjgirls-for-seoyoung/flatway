import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const FlatWayApp());
}

class FlatWayApp extends StatelessWidget {
  const FlatWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlatWay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ConnectionTestScreen(),
    );
  }
}

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  bool _isLoading = true;
  int _hazardCount = 0;
  int _buildingCount = 0;
  String _statusMessage = 'Supabase 연결 확인 중...';

  @override
  void initState() {
    super.initState();
    _checkSupabaseConnection();
  }

  Future<void> _checkSupabaseConnection() async {
    try {
      final hazards = await SupabaseService.fetchHazards();
      final buildings = await SupabaseService.fetchBuildings();

      setState(() {
        _hazardCount = hazards.length;
        _buildingCount = buildings.length;
        _isLoading = false;
        _statusMessage = 'Supabase DB 연동 성공!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Supabase 연결 오류: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlatWay - 2단계 준비 완료'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isLoading
                    ? Icons.sync
                    : (_hazardCount > 0 ? Icons.check_circle : Icons.error),
                size: 64,
                color: _isLoading
                    ? Colors.blue
                    : (_hazardCount > 0 ? Colors.green : Colors.red),
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (!_isLoading) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.warning, color: Colors.orange),
                          title: const Text('등록된 단차/파손 제보 수'),
                          trailing: Text(
                            '$_hazardCount건',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.domain, color: Colors.blue),
                          title: const Text('등록된 건물 접근성 데이터 수'),
                          trailing: Text(
                            '$_buildingCount개',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                    });
                    _checkSupabaseConnection();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('데이터 다시 불러오기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
