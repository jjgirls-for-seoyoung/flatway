import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flatway_app/config/app_config.dart';
import 'package:flatway_app/services/place_search_service.dart';

const _me = LatLng(37.5303, 126.7225); // 작전역 부근

PlaceResult _p(String name, double lat, double lng) =>
    PlaceResult(name: name, address: '', location: LatLng(lat, lng));

// 카카오 로컬 API(keyword.json) 문서의 응답 형태
const _kakaoKeywordJson = '''
{
  "meta": {"total_count": 2, "pageable_count": 2, "is_end": true},
  "documents": [
    {
      "id": "8199523", "place_name": "작전여자고등학교", "category_name": "교육,학문 > 학교 > 고등학교",
      "category_group_code": "SC4", "category_group_name": "학교", "phone": "032-000-0000",
      "address_name": "인천 계양구 작전동 100", "road_address_name": "인천 계양구 계양대로 1",
      "x": "126.7298", "y": "37.5320", "distance": "700"
    },
    {
      "id": "1", "place_name": "작전여고앞", "category_group_name": "",
      "address_name": "인천 계양구 작전동 1", "road_address_name": "",
      "x": "126.7279", "y": "37.5318"
    }
  ]
}
''';

void main() {
  tearDown(() {
    PlaceSearchService.client = null;
    AppConfig.kakaoRestApiKeyOverride = null;
  });

  group('검색어 변형', () {
    test('띄어쓰기를 붙인 변형을 만든다', () {
      expect(PlaceSearchService.queryVariants('작전여자 고등학교'), ['작전여자 고등학교', '작전여자고등학교']);
    });

    test('학교 약칭을 정식 명칭으로 푼다', () {
      expect(PlaceSearchService.queryVariants('작전여고'), contains('작전여자고등학교'));
      expect(PlaceSearchService.queryVariants('작전초'), contains('작전초등학교'));
      expect(PlaceSearchService.queryVariants('계양고'), contains('계양고등학교'));
    });

    test('이미 정식 명칭이면 더 늘리지 않는다', () {
      expect(PlaceSearchService.queryVariants('작전초등학교'), ['작전초등학교']);
      expect(PlaceSearchService.queryVariants('인하대학교'), ['인하대학교']);
    });
  });

  group('유도리 있는 검색 (이름 + 종류)', () {
    test('이름 부분과 종류로 나눈다', () {
      final sp = PlaceSearchService.splitNameAndType('된밭공원')!;
      expect((sp.stem, sp.type), ('된밭', '공원'));
      final school = PlaceSearchService.splitNameAndType('작전여자 고등학교')!;
      expect((school.stem, school.type), ('작전', '여자고등학교'));
      expect(PlaceSearchService.splitNameAndType('계양구청')!.type, '구청');
      expect(PlaceSearchService.splitNameAndType('공원'), isNull); // 이름 부분이 없다
    });

    test('공원은 근린공원/어린이공원과 이름 부분만으로도 찾는다', () {
      expect(PlaceSearchService.fuzzyVariants('된밭공원'), ['된밭근린공원', '된밭어린이공원', '된밭']);
      expect(PlaceSearchService.fuzzyVariants('작전초등학교'), ['작전']);
      expect(PlaceSearchService.fuzzyVariants('한양'), isEmpty);
    });

    test('된밭공원은 된밭근린공원을 먼저 보여 준다 (이름과 종류가 모두 들어 있으면 일치로 본다)', () {
      final ranked = PlaceSearchService.rankResults('된밭공원', [
        _p('된밭마을', 37.5300, 126.7280),
        _p('된밭근린공원', 37.5325, 126.7287),
        _p('작전근린공원', 37.5290, 126.7260),
      ], _me);
      expect(ranked.first.name, '된밭근린공원');
    });

    test('1단계에서 못 찾으면 이름 부분으로 한 번 더 찾아 된밭근린공원을 찾는다', () async {
      final queries = <String>[];
      PlaceSearchService.client = MockClient((req) async {
        final q = req.url.queryParameters['q']!;
        queries.add(q);
        final features = (q == '된밭' || q == '된밭근린공원')
            ? [
                {
                  'properties': {'name': '된밭근린공원', 'countrycode': 'KR', 'city': '인천광역시'},
                  'geometry': {'coordinates': [126.7287, 37.5325]},
                },
              ]
            : [];
        return http.Response.bytes(utf8.encode(jsonEncode({'features': features})), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final r = await PlaceSearchService.search('된밭공원', near: _me);
      expect(r!.first.name, '된밭근린공원');
      expect(queries, contains('된밭')); // 2단계 보조 검색을 했다
    });

    test('이미 이름과 종류가 모두 맞는 결과가 있으면 보조 검색을 하지 않는다', () async {
      final queries = <String>[];
      PlaceSearchService.client = MockClient((req) async {
        queries.add(req.url.queryParameters['q']!);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'features': [
              {
                'properties': {'name': '작전여자고등학교', 'countrycode': 'KR'},
                'geometry': {'coordinates': [126.7298, 37.532]},
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await PlaceSearchService.search('작전여자고등학교', near: _me);
      expect(queries, isNot(contains('작전'))); // 이름 부분만의 넓은 검색은 하지 않았다
    });
  });

  group('결과 정렬/필터', () {
    test('한글로 검색하면 영어로만 된 결과는 버린다', () {
      final r = PlaceSearchService.rankResults('작전여자고등학교', [
        _p("Jakjeon Girls' High School", 37.532, 126.7298),
        _p('작전여자고등학교', 37.532, 126.7298),
      ], _me);
      expect(r.map((e) => e.name), ['작전여자고등학교']);
    });

    test('이름이 검색어와 가까운 것이 먼저, 같으면 내 위치에서 가까운 것이 먼저', () {
      final r = PlaceSearchService.rankResults('계양구청', [
        _p('계양구청앞', 37.538, 126.7397),
        _p('계양구청', 37.9000, 126.9000), // 정확히 일치하지만 멀다
        _p('계양구청', 37.5375, 126.7378), // 정확히 일치하고 가깝다
      ], _me);
      expect(r.first.location.latitude, closeTo(37.5375, 1e-6)); // 일치 + 가까움
      expect(r[1].location.latitude, closeTo(37.9, 1e-6)); // 일치 + 멂
      expect(r.last.name, '계양구청앞'); // 부분 일치
    });

    test('약칭을 푼 이름과 일치하는 결과가 더 가까운 엉뚱한 결과보다 먼저 나온다', () {
      final results = [
        _p('작전중고.여고앞', 37.5318, 126.7279), // 더 가깝지만 다른 곳
        _p('작전여자고등학교', 37.532, 126.7298),
      ];
      // 변형 없이는 둘 다 일치하지 않아 거리 순으로 엉뚱한 곳이 앞선다
      expect(PlaceSearchService.rankResults('작전여고', results, _me).first.name, '작전중고.여고앞');
      // 변형(작전여자고등학교)을 함께 보면 정확히 일치하는 학교가 먼저다
      final ranked = PlaceSearchService.rankResults('작전여고', results, _me,
          variants: PlaceSearchService.queryVariants('작전여고'));
      expect(ranked.first.name, '작전여자고등학교');
    });

    test('띄어쓰기가 달라도 같은 이름으로 본다', () {
      final r = PlaceSearchService.rankResults('작전여자 고등학교', [
        _p('작전고등학교', 37.5327, 126.7305),
        _p('작전여자고등학교', 37.532, 126.7298),
      ], _me);
      expect(r.first.name, '작전여자고등학교');
    });
  });

  group('카카오 응답', () {
    test('장소 검색 응답을 이름, 분류, 도로명 주소, 좌표로 바꾼다', () {
      final doc = (jsonDecode(_kakaoKeywordJson)['documents'] as List).first as Map<String, dynamic>;
      final place = PlaceSearchService.parseKakaoDocument(doc)!;
      expect(place.name, '작전여자고등학교');
      expect(place.address, '학교 · 인천 계양구 계양대로 1');
      expect(place.location.latitude, closeTo(37.5320, 1e-6));
      expect(place.location.longitude, closeTo(126.7298, 1e-6));
    });

    test('도로명 주소가 없으면 지번 주소를 쓰고, 분류가 비면 주소만 보인다', () {
      final doc = (jsonDecode(_kakaoKeywordJson)['documents'] as List).last as Map<String, dynamic>;
      expect(PlaceSearchService.parseKakaoDocument(doc)!.address, '인천 계양구 작전동 1');
    });

    test('주소 검색 응답(place_name 없음)은 이름이 곧 주소다', () {
      final place = PlaceSearchService.parseKakaoDocument({
        'address_name': '인천 계양구 계양대로 100',
        'x': '126.73',
        'y': '37.53',
      })!;
      expect(place.name, '인천 계양구 계양대로 100');
      expect(place.address, '');
    });

    test('좌표가 없는 항목은 버린다', () {
      expect(PlaceSearchService.parseKakaoDocument({'place_name': '어딘가', 'x': '', 'y': ''}), isNull);
    });
  });

  group('검색 흐름', () {
    test('키가 있으면 카카오를 먼저 쓰고, 인증 헤더를 보낸다', () async {
      AppConfig.kakaoRestApiKeyOverride = 'test-key';
      final seen = <http.Request>[];
      PlaceSearchService.client = MockClient((req) async {
        seen.add(req);
        return http.Response.bytes(utf8.encode(_kakaoKeywordJson), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final r = await PlaceSearchService.search('작전여자 고등학교', near: _me);
      expect(r!.first.name, '작전여자고등학교');
      expect(seen, hasLength(1)); // 카카오에서 결과를 받았으니 무료 검색은 부르지 않는다
      expect(seen.single.url.host, 'dapi.kakao.com');
      expect(seen.single.headers['Authorization'], 'KakaoAK test-key');
      expect(seen.single.url.queryParameters['query'], '작전여자 고등학교');
      expect(seen.single.url.queryParameters['x'], isNotNull); // 내 위치 기준
    });

    test('카카오가 실패(예: 키 오류)하면 무료 검색으로 대신한다', () async {
      AppConfig.kakaoRestApiKeyOverride = 'bad-key';
      final hosts = <String>[];
      PlaceSearchService.client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'dapi.kakao.com') {
          return http.Response('{"errorType":"AccessDeniedError"}', 401);
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'features': [
              {
                'properties': {'name': '작전여자고등학교', 'countrycode': 'KR', 'city': '인천광역시'},
                'geometry': {'coordinates': [126.7298, 37.532]},
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final r = await PlaceSearchService.search('작전여고', near: _me);
      expect(r!.map((e) => e.name), ['작전여자고등학교']);
      expect(hosts, contains('dapi.kakao.com'));
      expect(hosts, contains('photon.komoot.io'));
    });

    test('키가 없으면 카카오를 부르지 않고, 띄어쓰기 변형도 함께 검색한다', () async {
      final queries = <String>[];
      PlaceSearchService.client = MockClient((req) async {
        expect(req.url.host, 'photon.komoot.io');
        queries.add(req.url.queryParameters['q']!);
        return http.Response('{"features":[]}', 200);
      });

      final r = await PlaceSearchService.search('작전여자 고등학교', near: _me);
      expect(r, isEmpty);
      expect(queries, containsAll(['작전여자 고등학교', '작전여자고등학교']));
    });

    test('모든 검색이 네트워크 오류면 null(실패)로 알린다', () async {
      PlaceSearchService.client = MockClient((req) async => http.Response('error', 500));
      expect(await PlaceSearchService.search('작전역', near: _me), isNull);
    });
  });
}
