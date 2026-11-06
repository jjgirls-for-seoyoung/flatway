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
    await ensureGuestSession();
    // Sync offline queued hazards when app starts
    syncPendingHazards();
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// 이메일로 정식 로그인한 사용자인지 (익명 게스트는 false)
  static bool get isSignedInWithEmail {
    final user = client.auth.currentUser;
    return user != null && !user.isAnonymous;
  }

  /// 세션이 없으면 익명(게스트) 세션을 만든다. 실패해도 앱 사용에는 영향 없음.
  /// (Supabase 대시보드에서 Anonymous sign-ins 활성화 필요)
  static Future<void> ensureGuestSession() async {
    try {
      if (client.auth.currentSession != null) return;
      await client.auth.signInAnonymously().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Guest session unavailable (continuing without): $e');
    }
  }

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

  // Upload hazard photo bytes to Supabase Storage
  static Future<String?> uploadHazardPhotoBytes(Uint8List bytes) async {
    try {
      final fileName = 'hazard_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await client.storage.from('hazard-photos').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      final publicUrl = client.storage.from('hazard-photos').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading photo to Supabase Storage: $e');
      return null;
    }
  }

  // Submit a new hazard report to Supabase with offline queue fallback
  static Future<bool> insertHazard(Map<String, dynamic> hazardData) async {
    try {
      await _insertHazardRow(hazardData);
      syncPendingHazards();
      return true;
    } catch (e) {
      debugPrint('Error inserting hazard to Supabase. Saving to offline queue: $e');
      await _savePendingOfflineHazard(hazardData);
      return true; // Saved locally
    }
  }

  /// hazards 행을 넣는다. 리워드용 `source` 컬럼이 아직 DB에 없으면(스키마 6번 미적용)
  /// 그 필드만 빼고 다시 시도해서 기존 제보 기능이 깨지지 않게 한다.
  static Future<void> _insertHazardRow(Map<String, dynamic> hazardData) async {
    try {
      await client.from('hazards').insert(hazardData);
    } on PostgrestException catch (e) {
      if (hazardData.containsKey('source') && e.message.contains('source')) {
        final fallback = Map<String, dynamic>.from(hazardData)..remove('source');
        await client.from('hazards').insert(fallback);
      } else {
        rethrow;
      }
    }
  }

  /// 내 포인트 (이메일 로그인 계정만 조회 가능). 로그인 전이거나 스키마 6번 미적용이면 null.
  static Future<int?> fetchMyPoints() async {
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    try {
      final row = await client
          .from('profiles')
          .select('points')
          .eq('user_id', user.id)
          .maybeSingle();
      return (row?['points'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('Error fetching points: $e');
      return null;
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
          await _insertHazardRow(map);
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
