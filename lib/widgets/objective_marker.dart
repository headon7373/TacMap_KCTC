import 'package:flutter/material.dart';

/// 월드오브탱크 점령 표시 방식. 색 링 안에 거점 문자 하나.
/// 아군=초록, 적군=빨강, 중립=흰색. 전투 중에 색만 보고 판단할 수 있다.
class ObjectiveMarker extends StatelessWidget {
  const ObjectiveMarker({
    super.key,
    required this.name,
    required this.color,
    this.size = 40,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
              border: Border.all(color: color, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: name.length > 1 ? size * 0.3 : size * 0.5,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 분대 리스폰 지점. 거점과 구분되도록 사각 배지로 그린다.
class SpawnMarker extends StatelessWidget {
  const SpawnMarker({
    super.key,
    required this.teamName,
    required this.color,
  });

  final String teamName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.home, color: color, size: 16),
        ),
        Text(
          teamName,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
          ),
        ),
      ],
    );
  }
}
