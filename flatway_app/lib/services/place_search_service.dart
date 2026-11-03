import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// 검색된(또는 최근에 고른) 장소 하나.
class PlaceResult {
  final String name;
  final String address;
  final LatLng location;

  const PlaceResult({
    required this.name,
    required this.address,
    required this.location,
  });

  /// 같은 장소로 볼 수 있는지 (이름이 같고 약 150m 이내)
  bool isSamePlaceAs(PlaceResult other) =>
      name == other.name &&
      const Distance().as(LengthUnit.Meter, location, other.location) < 150;

  String toJsonString() => jsonEncode({
    'name': name,
    'address': address,
    'lat': location.latitude,
    'lng': location.longitude,
  });

  static PlaceResult? fromJsonString(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return PlaceResult(
        name: m['name'] as String,
        address: (m['address'] ?? '') as String,
        location: LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 장소 이름 검색. OpenStreetMap 기반 Photon(komoot) 지오코더를 사용한다.
/// 키가 필요 없고 웹(CORS)에서도 동작한다. 내 위치 주변 결과를 우선한다.
class PlaceSearchService {
  static const _endpoint = 'https://photon.komoot.io/api/';

  /// 실패(네트워크 오류 등)하면 null, 결과가 없으면 빈 리스트.
  static Future<List<PlaceResult>?> search(String query, {LatLng? near}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    try {
      final params = <String, String>{'q': q, 'limit': '10'};
      if (near != null) {
        params['lat'] = near.latitude.toString();
        params['lon'] = near.longitude.toString();
      }
      // Photon은 기본 Dart User-Agent를 403으로 막는다. 웹은 브라우저가 User-Agent를 정하므로 제외.
      final response = await http
          .get(
            Uri.parse(_endpoint).replace(queryParameters: params),
            headers: kIsWeb ? null : {'User-Agent': 'FlatWay/1.0 (accessible route app)'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final features =
          (jsonDecode(response.body)['features'] as List?) ?? const [];
      final results = <PlaceResult>[];
      for (final f in features) {
        final props = (f['properties'] ?? {}) as Map<String, dynamic>;
        if (props['countrycode'] != 'KR') continue;
        final coords = (f['geometry']?['coordinates'] as List?);
        if (coords == null || coords.length < 2) continue;

        final street = props['street'] as String?;
        final number = props['housenumber'] as String?;
        final name =
            (props['name'] as String?) ??
            [street, number].whereType<String>().join(' ').trim();
        if (name.isEmpty) continue;

        final address = [
          if (street != null && props['name'] != null)
            [street, number].whereType<String>().join(' '),
          props['district'] ?? props['locality'],
          props['city'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

        final place = PlaceResult(
          name: name,
          address: address,
          location: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
        );
        if (!results.any(place.isSamePlaceAs)) results.add(place);
        if (results.length >= 8) break;
      }
      return results;
    } catch (e) {
      debugPrint('Place search failed: $e');
      return null;
    }
  }
}
