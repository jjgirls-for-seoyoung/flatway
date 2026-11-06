import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://wevesokdfrrtfmjbcprq.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_LEd-uwmLGwAGRbNA9tu4OA_0xshEJU1';
  static const String _pendingHazardsKey = 'pending_offline_hazards';
  static const String _myReportsPrefix = 'my_reports_v1_';

  /// 게스트로 방금 제보한 내용. 메모리에만 있어서 앱을 닫으면 사라진다.
  /// 제보 직후 이메일로 로그인하면 "내 계정으로 가져올까요?"를 물을 때 쓴다.
  static Map<String, dynamic>? lastGuestReport;

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

  static String? get currentUserId => client.auth.currentUser?.id;

  /// 로그인하지 않았거나 익명(게스트) 상태인지
  static bool get isGuest {
    final user = client.auth.currentUser;
    return user == null || user.isAnonymous;
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
  // [remember]가 true면 사용자가 직접 한 제보로 보고 계정별 '내 제보'에 기록한다.
  static Future<bool> insertHazard(Map<String, dynamic> hazardData, {bool remember = true}) async {
    final reporterId = currentUserId;
    final guest = isGuest;
    try {
      await _insertHazardRow(hazardData);
      syncPendingHazards();
    } catch (e) {
      debugPrint('Error inserting hazard to Supabase. Saving to offline queue: $e');
      await _savePendingOfflineHazard(hazardData);
    }
    if (remember) {
      await _addMyReport(reporterId, hazardData);
      if (guest) lastGuestReport = Map<String, dynamic>.from(hazardData);
    }
    return true; // Saved on the server or locally
  }

  static String _myReportsKey(String? userId) => '$_myReportsPrefix${userId ?? 'local'}';

  static Future<void> _addMyReport(String? userId, Map<String, dynamic> hazard) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _myReportsKey(userId);
      final list = prefs.getStringList(key) ?? [];
      list.insert(
        0,
        jsonEncode({
          'type': hazard['type'],
          'latitude': hazard['latitude'],
          'longitude': hazard['longitude'],
          'description': hazard['description'],
          'reported_at': hazard['reported_at'],
        }),
      );
      await prefs.setStringList(key, list.take(30).toList());
    } catch (e) {
      debugPrint('Error saving my report: $e');
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

  /// 이 기기에서 해당 계정으로 한 제보 목록 (최신순)
  static Future<List<Map<String, dynamic>>> myReports(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_myReportsKey(userId)) ?? const [])
          .map((e) => Map<String, dynamic>.from(jsonDecode(e) as Map))
          .toList();
    } catch (e) {
      debugPrint('Error loading my reports: $e');
      return [];
    }
  }

  /// 게스트로 방금 한 제보를 지금 로그인한 계정의 '내 제보'로 가져온다.
  static Future<void> claimLastGuestReport() async {
    final report = lastGuestReport;
    final uid = currentUserId;
    lastGuestReport = null;
    if (report == null || uid == null) return;
    await _addMyReport(uid, report);
  }

  static void dismissLastGuestReport() => lastGuestReport = null;

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
