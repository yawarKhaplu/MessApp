import 'package:flutter/material.dart';

import '../theme.dart';

/// A soft shimmering placeholder shown while data loads.
///
/// Hand-rolled rather than pulled from a package so it adds no dependency and
/// matches the app's existing colours exactly.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final Color? color;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.color,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? AppTheme.divider;
    final shine = Color.lerp(base, Colors.white, 0.65)!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Slide the highlight across the box and wrap it around.
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.6),
              end: Alignment(t + 1, 0.6),
              colors: [base, shine, base],
              stops: const [0.15, 0.5, 0.85],
            ),
          ),
        );
      },
    );
  }
}

/// Placeholder for just the chart and its metrics.
///
/// Deliberately does not cover the header or the toggles: those need no query,
/// so they render immediately and only the part that actually waits is dimmed.
class ChartAreaSkeleton extends StatelessWidget {
  const ChartAreaSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 12; i++) ...[
                Expanded(
                  child: SkeletonBox(
                    height: 40 + ((i * 37) % 70),
                    radius: 4,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 34, radius: 10)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 34, radius: 10)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 34, radius: 10)),
          ],
        ),
        const SizedBox(height: 14),
        const SkeletonBox(height: 40, radius: 12),
      ],
    );
  }
}

/// Placeholder for the numbers inside the month outlook card.
class OutlookBodySkeleton extends StatelessWidget {
  const OutlookBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 46, radius: 10)),
            SizedBox(width: 16),
            Expanded(child: SkeletonBox(height: 46, radius: 10)),
          ],
        ),
        SizedBox(height: 18),
        SkeletonBox(height: 12, radius: 6),
        SizedBox(height: 16),
        SkeletonBox(height: 48, radius: 14),
      ],
    );
  }
}