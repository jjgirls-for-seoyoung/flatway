import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://wevesokdfrrtfmjbcprq.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_LEd-uwmLGwAGRbNA9tu4OA_0xshEJU1';
  static const String _pendingHazardsKey = 'pending_offline_hazards';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
    // Sync offline queued hazards when app starts
    syncPendingHazards();
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

  // Submit a new hazard report to Supabase with offline queue fallback
  static Future<bool> insertHazard(Map<String, dynamic> hazardData) async {
    try {
      await client.from('hazards').insert(hazardData);
      // Attempt syncing any previously queued offline items
      syncPendingHazards();
      return true;
    } catch (e) {
      debugPrint('Error inserting hazard to Supabase. Saving to offline queue: $e');
      await _savePendingOfflineHazard(hazardData);
      return true; // Saved locally
    }
  }

  // Save offline pending report to SharedPreferences
  static Future<void> _savePendingOfflineHazard(Map<String, dynamic> hazardData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_pendingHazardsKey) ?? [];
      list.add(jsonEncode(hazardData));
      await prefs.setStringList(_pendingHazardsKey, list);
    } catch (e) {
      debugPrint('Error saving offline hazard: $e');
    }
  }

  // Sync queued offline reports to Supabase when network is restored
  static Future<void> syncPendingHazards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_pendingHazardsKey) ?? [];
      if (list.isEmpty) return;

      final List<String> remaining = [];
      for (final itemStr in list) {
        try {
          final Map<String, dynamic> map = jsonDecode(itemStr);
          await client.from('hazards').insert(map);
        } catch (e) {
          debugPrint('Failed to sync item, keeping in offline queue: $e');
          remaining.add(itemStr);
        }
      }
      await prefs.setStringList(_pendingHazardsKey, remaining);
      debugPrint('Offline hazards sync cycle completed. Remaining: ${remaining.length}');
    } catch (e) {
      debugPrint('Error in syncPendingHazards: $e');
    }
  }
}
