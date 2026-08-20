import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://wevesokdfrrtfmjbcprq.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_LEd-uwmLGwAGRbNA9tu4OA_0xshEJU1';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  // Fetch all hazard reports from Supabase
  static Future<List<Map<String, dynamic>>> fetchHazards() async {
    try {
      final data = await client
          .from('hazards')
          .select('*')
          .order('reported_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Error fetching hazards from Supabase: $e');
      return [];
    }
  }

  // Fetch all building accessibility data from Supabase
  static Future<List<Map<String, dynamic>>> fetchBuildings() async {
    try {
      final data = await client.from('buildings').select('*');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Error fetching buildings from Supabase: $e');
      return [];
    }
  }

  // Submit a new hazard report to Supabase
  static Future<bool> insertHazard(Map<String, dynamic> hazardData) async {
    try {
      await client.from('hazards').insert(hazardData);
      return true;
    } catch (e) {
      debugPrint('Error inserting hazard to Supabase: $e');
      return false;
    }
  }
}
