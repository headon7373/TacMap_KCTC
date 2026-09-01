import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 한 사람의 위치와 "지금 보고 있는 방향"을 함께 그린다.
/// 부채꼴이 시선 방향, 가운데 점이 위치. 팀 색으로 구분한다.
/// 3단계에서 아군 마커도 같은 위젯을 쓴다.
class HeadingMarker extends StatelessWidget {
  const HeadingMarker({
    super.key,
    required this.color,
    this.headingDegrees,
    this.label,
    this.dead = false,
    this.size = 64,
  });

  final Color color;

  /// 화면 기준 각도(0 = 위쪽). null이면 방향을 모르는 상태로 점만 그린다.
  final double? headingDegrees;
  final String? label;
  final bool dead;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effective = dead ? Colors.grey : color;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (headingDegrees != null && !dead)
            Transform.rotate(
              angle: headingDegrees! * math.pi / 180,
              child: CustomPaint(
                size: Size(size, size),
                painter: _ConePainter(color: effective),
              ),
            ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: effective,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
          if (dead)
            const Icon(Icons.close, size: 20, color: Colors.white),
          if (label != null)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 위쪽(-90도)을 향하는 반투명 부채꼴. 시야각 70도.
class _ConePainter extends CustomPainter {
  const _ConePainter({required this.color});

  final Color color;

  static const _sweepDegrees = 70.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweep = _sweepDegrees * math.pi / 180;
    // 캔버스 0라디안은 오른쪽이므로 위쪽을 향하도록 -90도 돌린다.
    final start = -math.pi / 2 - sweep / 2;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ConePainter oldDelegate) => oldDelegate.color != color;
}
