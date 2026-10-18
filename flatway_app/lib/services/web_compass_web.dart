import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 브라우저 deviceorientation 기반 나침반.
/// - iOS Safari: 사용자 터치 이후 requestPermission() 필요, webkitCompassHeading 사용
/// - Android Chrome: deviceorientationabsolute 의 alpha(반시계) -> 방위각으로 변환
class WebCompass {
  static Future<bool> requestPermission() async {
    try {
      final ctor = globalContext['DeviceOrientationEvent'];
      if (ctor == null || ctor.isUndefinedOrNull) return false;
      final ctorObj = ctor as JSObject;
      if (ctorObj.has('requestPermission')) {
        final result = await (ctorObj.callMethod('requestPermission'.toJS)
                as JSPromise<JSAny?>)
            .toDart;
        return (result as JSString).toDart == 'granted';
      }
      // 권한 요청이 필요 없는 브라우저(Android 등)
      return true;
    } catch (_) {
      return false;
    }
  }

  static double? _num(JSObject event, String key) {
    final v = event[key];
    if (v == null || v.isUndefinedOrNull || !v.isA<JSNumber>()) return null;
    return (v as JSNumber).toDartDouble;
  }

  static Stream<double> get headings {
    late StreamController<double> controller;
    final cbs = <String, JSFunction>{};

    void handle(JSObject event) {
      // iOS
      final webkit = _num(event, 'webkitCompassHeading');
      if (webkit != null) {
        controller.add(webkit);
        return;
      }
      // Android (absolute 이벤트에서만 신뢰)
      final alpha = _num(event, 'alpha');
      if (alpha != null && event['absolute'].dartify() == true) {
        controller.add((360 - alpha) % 360);
      }
    }

    controller = StreamController<double>(
      onListen: () {
        for (final name in ['deviceorientationabsolute', 'deviceorientation']) {
          final cb = ((JSObject e) => handle(e)).toJS;
          cbs[name] = cb;
          globalContext.callMethod('addEventListener'.toJS, name.toJS, cb);
        }
      },
      onCancel: () {
        cbs.forEach((name, cb) {
          globalContext.callMethod('removeEventListener'.toJS, name.toJS, cb);
        });
        cbs.clear();
      },
    );
    return controller.stream;
  }
}
