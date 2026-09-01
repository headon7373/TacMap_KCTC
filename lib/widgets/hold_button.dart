import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

/// 정해진 시간 동안 누르고 있어야 실행되는 버튼.
///
/// 진행 게이지는 버튼에 그리지 않는다. 누르고 있는 손가락이 가려서 안 보이기 때문에,
/// [onProgress]로 진행률만 넘기고 화면 중앙에 크게 그리는 쪽이 훨씬 잘 보인다.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.background,
    required this.onHoldComplete,
    required this.onProgress,
    this.holdDuration = const Duration(seconds: 3),
    this.size = 84,
  });

  /// 아이콘 대신 글자/이모지를 쓴다. 머티리얼에는 해골 아이콘이 없다.
  final String glyph;
  final String label;
  final Color background;
  final VoidCallback onHoldComplete;
  final ValueChanged<double> onProgress;
  final Duration holdDuration;
  final double size;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )
    ..addListener(() => widget.onProgress(_controller.value))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Vibration.vibrate(duration: 150);
        widget.onHoldComplete();
        _controller.reset();
        widget.onProgress(0);
      }
    });

  bool _pressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(_) {
    setState(() => _pressed = true);
    _controller.forward();
  }

  void _cancel([_]) {
    setState(() => _pressed = false);
    if (_controller.isAnimating) {
      _controller.reset();
      widget.onProgress(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _start,
      onTapUp: _cancel,
      onTapCancel: _cancel,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed
              ? Color.lerp(widget.background, Colors.white, 0.15)
              : widget.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.glyph,
              style: TextStyle(fontSize: widget.size * 0.36),
            ),
            Text(
              widget.label,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.size * 0.17,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              '3초 누르기',
              style: TextStyle(
                color: Colors.white54,
                fontSize: widget.size * 0.12,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 화면 한가운데에 크게 뜨는 홀드 게이지.
/// 버튼 위가 아니라 여기에 그려야 누르는 손에 가리지 않는다.
class HoldGauge extends StatelessWidget {
  const HoldGauge({
    super.key,
    required this.progress,
    required this.label,
    required this.color,
    required this.seconds,
  });

  final double progress;
  final String label;
  final Color color;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final remaining = ((1 - progress) * seconds).ceil();
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: Colors.white24,
                  color: color,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$remaining',
                    style: TextStyle(
                      color: color,
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
