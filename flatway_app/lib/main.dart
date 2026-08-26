import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
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
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF047857),
          primary: const Color(0xFF047857),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
