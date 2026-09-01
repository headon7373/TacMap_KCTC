import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

/// 정해진 시간 동안 누르고 있어야 실행되는 버튼.
///
/// 일부러 **원형**으로 만들었다. 옆에 있는 표식·거점 버튼은 사각형이라
/// 장갑 낀 손이나 곁눈질로도 모양만 보고 구분할 수 있다.
/// 사망 처리는 잘못 눌리면 팀 전체 판단을 흔들기 때문에 오조작을 막아야 한다.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onHoldComplete,
    this.holdDuration = const Duration(seconds: 3),
    this.size = 76,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onHoldComplete;
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
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Vibration.vibrate(duration: 120);
        widget.onHoldComplete();
        _controller.reset();
      }
    });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(_) => _controller.forward();

  void _cancel([_]) {
    if (_controller.isAnimating) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _start,
      onTapUp: _cancel,
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          final remaining =
              ((1 - progress) * widget.holdDuration.inSeconds).ceil();
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 누르고 있는 동안 링이 차오른다.
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    backgroundColor: widget.color.withValues(alpha: 0.35),
                    color: Colors.white,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    // 채움이 아니라 어두운 바탕 — 옆의 채움 사각 버튼과 확실히 다르다.
                    color: Color.lerp(
                      const Color(0xFF1A1A1A),
                      widget.color,
                      0.25 + progress * 0.6,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color, width: 2.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, color: widget.color, size: 22),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        progress > 0 ? '$remaining' : '3초',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 9,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
