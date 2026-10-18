import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 튜토리얼의 한 단계. [targetKey]가 null이면 화면 중앙에 안내 카드만 표시한다.
class TourStep {
  final GlobalKey? targetKey;
  final IconData icon;
  final String title;
  final String description;

  const TourStep({
    this.targetKey,
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// 첫 실행 시 기능을 말풍선으로 단계별 안내하는 코치마크 튜토리얼.
class OnboardingTour {
  static const _prefKey = 'onboarding_tour_done_v1';
  static const _green = Color(0xFF047857);

  static Future<bool> shouldAutoShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_prefKey) ?? false);
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }

  /// 화면에 없는 대상(예: 웹에서 숨겨진 버튼)은 건너뛰고 튜토리얼을 시작한다.
  static void show(BuildContext context, List<TourStep> allSteps) {
    final steps = allSteps
        .where(
          (s) => s.targetKey == null || s.targetKey!.currentContext != null,
        )
        .toList();
    if (steps.isEmpty) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: steps,
        // dontShowAgain=false(X 버튼)면 다음 접속 때 다시 안내한다.
        onClose: (dontShowAgain) {
          entry.remove();
          if (dontShowAgain) _markDone();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final void Function(bool dontShowAgain) onClose;

  const _TourOverlay({required this.steps, required this.onClose});

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _index = 0;

  TourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  Rect? _targetRect() {
    final ctx = _step.targetKey?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    if (_isLast) {
      widget.onClose(true);
    } else {
      setState(() => _index++);
    }
  }

  void _restart() => setState(() => _index = 0);

  void _prev() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final target = _targetRect()?.inflate(6);
    final bubbleWidth = (size.width - 32).clamp(0.0, 330.0);

    Widget positioned;
    if (target == null) {
      positioned = Center(child: _buildBubble(bubbleWidth, null, false));
    } else {
      final below = target.center.dy < size.height / 2;
      final left = (target.center.dx - bubbleWidth / 2).clamp(
        16.0,
        size.width - bubbleWidth - 16,
      );
      final tailX = (target.center.dx - left).clamp(28.0, bubbleWidth - 28);
      final content = _buildBubble(bubbleWidth, tailX, below);
      positioned = below
          ? Positioned(top: target.bottom + 2, left: left, child: content)
          : Positioned(
              bottom: size.height - target.top + 2,
              left: left,
              child: content,
            );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 배경을 어둡게 하고 대상 영역만 도려낸다. 터치는 막는다.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _SpotlightPainter(target)),
            ),
          ),
          positioned,
        ],
      ),
    );
  }

  /// [tailX]가 null이면 꼬리 없는 카드, 아니면 대상 쪽을 가리키는 말풍선.
  Widget _buildBubble(double width, double? tailX, bool tailUp) {
    final total = widget.steps.length;
    const tailH = 12.0;
    return CustomPaint(
      painter: _BubblePainter(tailX: tailX, tailUp: tailUp, tailHeight: tailH),
      child: Container(
        width: width,
        padding: EdgeInsets.fromLTRB(
          16,
          14 + (tailX != null && tailUp ? tailH : 0),
          16,
          12 + (tailX != null && !tailUp ? tailH : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: OnboardingTour._green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _step.icon,
                    color: OnboardingTour._green,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _step.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111111),
                    ),
                  ),
                ),
                Text(
                  '${_index + 1}/$total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777777),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => widget.onClose(false),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFF777777),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _step.description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => widget.onClose(true),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF777777),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('다시 보지 않기', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                if (_isLast)
                  TextButton(
                    onPressed: _restart,
                    style: TextButton.styleFrom(
                      foregroundColor: OnboardingTour._green,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      '다시 보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_index > 0 && !_isLast)
                  TextButton(
                    onPressed: _prev,
                    style: TextButton.styleFrom(
                      foregroundColor: OnboardingTour._green,
                    ),
                    child: const Text(
                      '이전',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OnboardingTour._green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    _isLast ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  _SpotlightPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      path.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(10)));
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.3));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(10)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.hole != hole;
}

class _BubblePainter extends CustomPainter {
  final double? tailX;
  final bool tailUp;
  final double tailHeight;

  _BubblePainter({
    required this.tailX,
    required this.tailUp,
    required this.tailHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 14.0;
    final hasTail = tailX != null;
    final top = hasTail && tailUp ? tailHeight : 0.0;
    final bottom = size.height - (hasTail && !tailUp ? tailHeight : 0.0);
    final body = RRect.fromLTRBR(
      0,
      top,
      size.width,
      bottom,
      const Radius.circular(r),
    );

    final path = Path()..addRRect(body);
    if (hasTail) {
      final x = tailX!;
      final tail = Path();
      if (tailUp) {
        tail.moveTo(x - 9, top);
        tail.quadraticBezierTo(x - 3, top, x - 4, 0);
        tail.quadraticBezierTo(x + 2, top - 1, x + 12, top);
      } else {
        tail.moveTo(x - 12, bottom);
        tail.quadraticBezierTo(x - 2, bottom + 1, x + 4, size.height);
        tail.quadraticBezierTo(x + 3, bottom, x + 9, bottom);
      }
      tail.close();
      path.addPath(tail, Offset.zero);
    }
    final merged = Path.combine(PathOperation.union, path, Path());

    canvas.drawShadow(merged, Colors.black54, 6, true);
    canvas.drawPath(merged, Paint()..color = Colors.white);
    canvas.drawPath(
      merged,
      Paint()
        ..color = OnboardingTour._green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.tailX != tailX || old.tailUp != tailUp;
}
