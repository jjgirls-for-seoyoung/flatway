import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';

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

/// 장소 이름 검색.
/// - 카카오 REST API 키가 있으면 카카오 로컬 검색(네이버·카카오맵과 같은 한국 장소 데이터)을 쓴다.
/// - 키가 없거나 카카오가 실패/무결과면 OpenStreetMap 기반 Photon 검색으로 대신한다.
///   이때는 띄어쓰기·약칭 변형 검색, 영어 전용 결과 제외, 이름 일치도·거리 정렬로 품질을 높인다.
class PlaceSearchService {
  static const _kakaoKeyword = 'https://dapi.kakao.com/v2/local/search/keyword.json';
  static const _kakaoAddress = 'https://dapi.kakao.com/v2/local/search/address.json';
  static const _photon = 'https://photon.komoot.io/api/';

  /// 테스트에서 가짜 HTTP 클라이언트를 끼우기 위한 값.
  @visibleForTesting
  static http.Client? client;

  static Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      client != null ? client!.get(uri, headers: headers) : http.get(uri, headers: headers);

  /// 실패(네트워크 오류 등)하면 null, 결과가 없으면 빈 리스트.
  static Future<List<PlaceResult>?> search(String query, {LatLng? near}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    if (AppConfig.hasKakao) {
      final kakao = await _searchKakao(q, near);
      if (kakao != null && kakao.isNotEmpty) return kakao;
      // 카카오가 실패했거나 결과가 없으면 무료 검색으로 한 번 더 찾는다.
    }
    return _searchOsm(q, near);
  }

  // ---------------------------------------------------------------- 카카오

  /// 카카오 응답(keyword/address 공통) 한 건을 장소로 바꾼다. 좌표가 없으면 null.
  @visibleForTesting
  static PlaceResult? parseKakaoDocument(Map<String, dynamic> d) {
    final lat = double.tryParse('${d['y']}');
    final lng = double.tryParse('${d['x']}');
    if (lat == null || lng == null) return null;

    // keyword.json: place_name / address.json: address_name 만 있다.
    final placeName = (d['place_name'] as String?)?.trim();
    final road = (d['road_address_name'] as String?)?.trim() ?? '';
    final lot = (d['address_name'] as String?)?.trim() ?? '';
    final addr = road.isNotEmpty ? road : lot;
    final category = (d['category_group_name'] as String?)?.trim() ?? '';

    final name = (placeName != null && placeName.isNotEmpty) ? placeName : addr;
    if (name.isEmpty) return null;
    final subtitle = placeName != null && placeName.isNotEmpty
        ? [if (category.isNotEmpty) category, addr].where((s) => s.isNotEmpty).join(' · ')
        : ''; // 주소 검색 결과는 이름이 곧 주소다
    return PlaceResult(name: name, address: subtitle, location: LatLng(lat, lng));
  }

  static Future<List<PlaceResult>?> _kakaoGet(String url, Map<String, String> params) async {
    try {
      final res = await _get(
        Uri.parse(url).replace(queryParameters: params),
        headers: {'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        debugPrint('Kakao search HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      final docs = (jsonDecode(utf8.decode(res.bodyBytes))['documents'] as List?) ?? const [];
      return docs
          .whereType<Map>()
          .map((d) => parseKakaoDocument(Map<String, dynamic>.from(d)))
          .whereType<PlaceResult>()
          .toList();
    } catch (e) {
      debugPrint('Kakao search failed: $e');
      return null;
    }
  }

  static Future<List<PlaceResult>?> _searchKakao(String q, LatLng? near) async {
    final params = <String, String>{'query': q, 'size': '10'};
    if (near != null) {
      // x,y를 주면 내 위치와의 거리 정보도 오고, 가까운 곳이 우선되도록 도움이 된다.
      params['x'] = near.longitude.toString();
      params['y'] = near.latitude.toString();
    }
    final keyword = await _kakaoGet(_kakaoKeyword, params);
    if (keyword != null && keyword.isNotEmpty) return keyword;

    // 장소가 아니라 "계양대로 100" 같은 주소일 수 있어 주소 검색도 해 본다.
    final address = await _kakaoGet(_kakaoAddress, {'query': q, 'size': '10'});
    if (address != null && address.isNotEmpty) return address;
    return keyword ?? address; // 둘 다 실패면 null, 둘 다 빈 결과면 빈 리스트
  }

  // ------------------------------------------------------------------- OSM

  /// 검색어의 변형들. 띄어쓰기를 없애고, 학교 약칭을 풀어서 여러 번 찾아 놓치는 곳을 줄인다.
  /// 예) "작전여자 고등학교" -> ["작전여자 고등학교", "작전여자고등학교"]
  ///     "작전여고" -> ["작전여고", "작전여자고등학교"]
  @visibleForTesting
  static List<String> queryVariants(String query) {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final out = <String>[q];

    void add(String v) {
      final t = v.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }

    final compact = q.replaceAll(' ', '');
    add(compact);

    // 약칭 -> 정식 명칭 (끝부분만 바꾼다)
    const suffixes = {
      '여고': '여자고등학교',
      '남고': '남자고등학교',
      '여중': '여자중학교',
      '여상': '여자상업고등학교',
      '초': '초등학교',
      '중': '중학교',
      '고': '고등학교',
      '대': '대학교',
    };
    for (final e in suffixes.entries) {
      if (compact.length > e.key.length && compact.endsWith(e.key)) {
        final stem = compact.substring(0, compact.length - e.key.length);
        // "초등학교"처럼 이미 정식 명칭이면 건드리지 않는다.
        if (!stem.endsWith('등학') && !stem.endsWith('학')) add('$stem${e.value}');
        break;
      }
    }
    return out.take(4).toList();
  }

  // 장소 이름 끝에 붙는 종류. 긴 것이 앞에 와야 한다. (예: 근린공원이 공원보다 먼저)
  static const _typeWords = [
    '여자고등학교', '남자고등학교', '초등학교', '중학교', '고등학교', '대학교',
    '근린공원', '어린이공원', '공원',
    '학교', '병원', '약국', '시장', '아파트', '교회', '성당', '도서관', '체육관',
    '주민센터', '구청', '시청', '우체국', '경찰서', '소방서', '마트', '편의점', '역',
  ];

  /// 검색어를 이름 부분과 종류로 나눈다. 예) "된밭공원" -> (stem: 된밭, type: 공원). 못 나누면 null.
  @visibleForTesting
  static ({String stem, String type})? splitNameAndType(String query) {
    final compact = query.replaceAll(RegExp(r'\s+'), '');
    for (final t in _typeWords) {
      if (compact.length >= t.length + 2 && compact.endsWith(t)) {
        return (stem: compact.substring(0, compact.length - t.length), type: t);
      }
    }
    return null;
  }

  /// 처음 검색에서 못 찾았을 때 쓰는 보조 검색어.
  /// 예) "된밭공원" -> ["된밭근린공원", "된밭어린이공원", "된밭"]
  /// (공원 이름은 "된밭근린공원"처럼 가운데에 종류가 끼는 경우가 많다)
  @visibleForTesting
  static List<String> fuzzyVariants(String query) {
    final sp = splitNameAndType(query);
    if (sp == null) return [];
    return [
      if (sp.type == '공원') ...['${sp.stem}근린공원', '${sp.stem}어린이공원'],
      sp.stem,
    ];
  }

  /// 이름에 이름 부분과 종류가 모두 들어 있는지. "된밭공원"이 "된밭근린공원"과 맞는다.
  static bool _matchesNameAndType(String name, ({String stem, String type})? sp) {
    if (sp == null) return false;
    final n = _norm(name);
    return n.contains(sp.stem) && n.contains(sp.type);
  }

  static bool _hasHangul(String s) => s.runes.any((r) => r >= 0xAC00 && r <= 0xD7A3);

  static String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 검색 결과 정렬/필터. 이름이 검색어와 가까운 순, 같으면 내 위치에서 가까운 순.
  /// [variants]는 약칭을 푼 이름 등 같은 뜻의 다른 검색어. 이 중 하나라도 일치하면 일치로 본다.
  @visibleForTesting
  static List<PlaceResult> rankResults(
    String query,
    List<PlaceResult> results,
    LatLng? near, {
    List<String> variants = const [],
  }) {
    final koreanQuery = _hasHangul(query);
    final names = {_norm(query), ...variants.map(_norm)}.where((n) => n.isNotEmpty).toList();
    final nameAndType = splitNameAndType(query);
    const dist = Distance();

    // 한글로 검색했는데 이름에 한글이 하나도 없는 결과(영어 표기 등)는 버린다.
    final filtered = results.where((r) => !koreanQuery || _hasHangul(r.name)).toList();

    int tier(PlaceResult r) {
      final n = _norm(r.name);
      var best = 3;
      for (final q in names) {
        final t = n == q ? 0 : (n.startsWith(q) ? 1 : (n.contains(q) ? 2 : 3));
        if (t < best) best = t;
      }
      if (best > 1 && _matchesNameAndType(r.name, nameAndType)) best = 1;
      return best;
    }

    double d(PlaceResult r) => near == null ? 0 : dist.as(LengthUnit.Meter, near, r.location);

    filtered.sort((a, b) {
      final t = tier(a).compareTo(tier(b));
      return t != 0 ? t : d(a).compareTo(d(b));
    });
    return filtered;
  }

  static Future<List<PlaceResult>?> _photonQuery(String q, LatLng? near) async {
    try {
      final params = <String, String>{'q': q, 'limit': '10'};
      if (near != null) {
        params['lat'] = near.latitude.toString();
        params['lon'] = near.longitude.toString();
      }
      // Photon은 기본 Dart User-Agent를 403으로 막는다. 웹은 브라우저가 User-Agent를 정하므로 제외.
      final response = await _get(
        Uri.parse(_photon).replace(queryParameters: params),
        headers: kIsWeb ? null : {'User-Agent': 'FlatWay/1.0 (accessible route app)'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final features = (jsonDecode(utf8.decode(response.bodyBytes))['features'] as List?) ?? const [];
      final results = <PlaceResult>[];
      for (final f in features) {
        final props = (f['properties'] ?? {}) as Map<String, dynamic>;
        if (props['countrycode'] != 'KR') continue;
        final coords = (f['geometry']?['coordinates'] as List?);
        if (coords == null || coords.length < 2) continue;

        final street = props['street'] as String?;
        final number = props['housenumber'] as String?;
        final name = (props['name'] as String?) ?? [street, number].whereType<String>().join(' ').trim();
        if (name.isEmpty) continue;

        final address = [
          if (street != null && props['name'] != null) [street, number].whereType<String>().join(' '),
          props['district'] ?? props['locality'],
          props['city'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

        results.add(PlaceResult(
          name: name,
          address: address,
          location: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        ));
      }
      return results;
    } catch (e) {
      debugPrint('Place search failed: $e');
      return null;
    }
  }

  /// 여러 검색어를 한꺼번에 찾아 합친다. 전부 실패하면 null.
  static Future<List<PlaceResult>?> _photonMerge(List<String> queries, LatLng? near) async {
    final responses = await Future.wait(queries.map((v) => _photonQuery(v, near)));
    if (responses.every((r) => r == null)) return null;
    final merged = <PlaceResult>[];
    for (final list in responses) {
      for (final p in list ?? const <PlaceResult>[]) {
        if (!merged.any(p.isSamePlaceAs)) merged.add(p);
      }
    }
    return merged;
  }

  static Future<List<PlaceResult>?> _searchOsm(String q, LatLng? near) async {
    // 1단계: 검색어 그대로 + 띄어쓰기/약칭 변형
    final variants = queryVariants(q);
    final merged = await _photonMerge(variants, near);
    if (merged == null) return null; // 전부 실패 = 네트워크 문제

    // 2단계: "된밭공원"처럼 이름과 종류가 붙어 있어 못 찾았다면, 이름 부분만으로 한 번 더 찾는다.
    //        (이름 + 종류가 모두 들어간 결과가 이미 있으면 요청을 늘리지 않는다)
    final sp = splitNameAndType(q);
    final extra = <String>[];
    if (sp != null && !merged.any((p) => _matchesNameAndType(p.name, sp))) {
      extra.addAll(fuzzyVariants(q).where((v) => !variants.contains(v)));
      final more = extra.isEmpty ? null : await _photonMerge(extra, near);
      for (final p in more ?? const <PlaceResult>[]) {
        if (!merged.any(p.isSamePlaceAs)) merged.add(p);
      }
    }
    return rankResults(q, merged, near, variants: [...variants, ...extra]).take(8).toList();
  }
}
