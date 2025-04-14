// This is a simple animation controller for the shimmer effect.
// --- Define the Gradient Transform ---
import 'package:flutter/material.dart';

class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  final double patternWidth; // Make pattern width configurable

  const _SlideGradientTransform({
    required this.slidePercent,
    required this.patternWidth,
  });

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // Calculate translation based on slidePercent and patternWidth
    // Ensures the pattern starts off-screen left and ends off-screen right
    final double totalTravel = 1.0 + patternWidth;
    final double dx = (slidePercent * totalTravel) - patternWidth;
    return Matrix4.translationValues(dx * bounds.width, 0.0, 0.0);
  }
}
// ---

/// A widget that applies a one-directional shimmer effect to its child.
class ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  final double gradientPatternWidth;

  const ShimmerWidget({
    required this.child,
    this.baseColor = const Color(0xFF212121),
    this.highlightColor = const Color(0xFFFFFFFF), // Slightly lighter highlight
    this.duration = const Duration(milliseconds: 1000),
    this.gradientPatternWidth = 0.5, // Default width of the moving band
    super.key,
  });

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: widget.duration, // Use duration from widget property
    )..repeat(); // Start one-directional repeat
  }

  @override
  void dispose() {
    _shimmerController.dispose(); // Dispose controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      // Pass the original child down to the builder
      child: widget.child,
      builder: (context, staticChild) {
        // Ensure we have a child to apply the mask to
        if (staticChild == null) {
          return const SizedBox.shrink();
        }
        return ShaderMask(
          blendMode: BlendMode.srcIn, // Apply gradient color to child's shape
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              // Use colors from widget properties
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [
                0.0, // Start base
                0.5, // Peak highlight in pattern center
                1.0, // End base
              ],
              // Apply the sliding transform
              transform: _SlideGradientTransform(
                slidePercent: _shimmerController.value,
                patternWidth:
                    widget.gradientPatternWidth, // Use configurable width
              ),
              // Optional: Clamp tileMode might prevent edge artifacts
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          // Apply the mask to the child passed to the ShimmerWidget
          child: staticChild,
        );
      },
    );
  }
}

//shimmer list widget for attendance screen
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({super.key});

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // Slower animation
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Widget _buildShimmerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2, // Reduced elevation
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[850]!, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject name shimmer
              AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  return Container(
                    width: double.infinity,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey[900]!,
                          Colors.grey[850]!,
                          Colors.grey[900]!,
                        ],
                        stops: [0.0, _shimmerController.value, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // Subject code shimmer
              AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  return Container(
                    width: 120,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey[900]!,
                          Colors.grey[850]!,
                          Colors.grey[900]!,
                        ],
                        stops: [0.0, _shimmerController.value, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Time, Teacher, Location info rows
              ...List.generate(
                3,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        index == 0
                            ? Icons.access_time
                            : index == 1
                            ? Icons.person_outline
                            : Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return Container(
                            width: 150,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey[900]!,
                                  Colors.grey[850]!,
                                  Colors.grey[900]!,
                                ],
                                stops: [0.0, _shimmerController.value, 1.0],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 3, // Show 3 skeleton cards
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }
}
