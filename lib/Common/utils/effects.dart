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

/// A widget that applies a one-directional shimmer effect to its child.
class ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  final double gradientPatternWidth;

  const ShimmerWidget({
    required this.child,
    this.baseColor = Colors.black,
    this.highlightColor = const Color(0xFFDEDEDE), // Slightly lighter highlight
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
          blendMode: BlendMode.srcATop, // Apply gradient color to child's shape
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

  // Define shimmer colors suitable for light theme
  final Color _shimmerBaseColor = Colors.grey.shade200; // Lighter base
  final Color _shimmerHighlightColor =
      Colors.grey.shade100; // Lighter highlight

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Slightly faster maybe?
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  // Helper to build the animated gradient
  LinearGradient _buildShimmerGradient() {
    return LinearGradient(
      colors: [_shimmerBaseColor, _shimmerHighlightColor, _shimmerBaseColor],
      stops: [
        _shimmerController.value - 0.3, // Adjust stops for desired effect
        _shimmerController.value,
        _shimmerController.value + 0.3,
      ],
      begin: const Alignment(-1.0, -0.3), // Adjust gradient angle if needed
      end: const Alignment(1.0, 0.3),
      tileMode: TileMode.clamp,
    );
  }

  // Helper to build a single shimmer placeholder box
  Widget _buildShimmerBox({required double height, double? width}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          height: height,
          width: width ?? double.infinity, // Default to full width
          decoration: BoxDecoration(
            // Use base color for the background of the box
            color: _shimmerBaseColor,
            // Apply the animated gradient
            gradient: _buildShimmerGradient(),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }

  Widget _buildShimmerCard() {
    // Use the CardTheme margin for spacing, remove outer Padding
    return Card(
      // Card styling (elevation, shape, border, margin, color)
      // is now inherited from Theme.of(context).cardTheme
      // Ensure CardTheme is defined correctly in main.dart
      // margin: EdgeInsets.zero, // Only if CardTheme margin is unwanted here
      clipBehavior: Clip.antiAlias, // Good practice with gradients/borders
      child: Padding(
        padding: const EdgeInsets.all(16), // Inner padding for content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject name shimmer (Larger height)
            _buildShimmerBox(height: 22), // Adjusted height
            const SizedBox(height: 8),

            // Subject code shimmer (Shorter width)
            _buildShimmerBox(height: 16, width: 100), // Adjusted height & width
            const SizedBox(height: 10),

            // Type Chip shimmer (Small rectangle)
            _buildShimmerBox(height: 20, width: 60),
            const SizedBox(height: 16),

            // Teacher/Semester Info rows (Text lines)
            _buildShimmerBox(height: 14, width: 180), // Adjusted height & width
            const SizedBox(height: 8),
            _buildShimmerBox(height: 14, width: 150), // Adjusted height & width
            const SizedBox(height: 16),

            // Classroom, Time, Date info rows (Icon + Text line)
            ...List.generate(
              3,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // Icon placeholder (using a simple grey box)
                    Container(
                      height: 18,
                      width: 18,
                      decoration: BoxDecoration(
                        color:
                            Colors
                                .grey
                                .shade300, // Slightly darker grey for icon placeholder
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Icon( // Or use actual icons with muted theme color
                    //   index == 0
                    //       ? Icons.group_outlined // Match actual icons used
                    //       : index == 1
                    //           ? Icons.access_time_outlined
                    //           : Icons.calendar_today_outlined,
                    //   size: 18,
                    //   // Use theme color with opacity for muted look
                    //   color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    // ),
                    const SizedBox(width: 8),
                    // Text line placeholder next to icon
                    Expanded(
                      // Allow it to take remaining space
                      child: _buildShimmerBox(height: 14), // Adjusted height
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Adjust padding based on CardTheme margin and desired list spacing
      padding: const EdgeInsets.symmetric(
        vertical: 8.0,
      ), // Minimal list padding
      itemCount: 4, // Show a few skeleton cards
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }
}

/// A custom shimmer loading widget specifically for the student attendance list.
class ListLoadingShimmer extends StatefulWidget {
  const ListLoadingShimmer({super.key});

  @override
  State<ListLoadingShimmer> createState() => _ListLoadingShimmerState();
}

class _ListLoadingShimmerState extends State<ListLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  // Use consistent colors with your other shimmer widgets
  final Color _shimmerBaseColor = Colors.grey.shade200;
  final Color _shimmerHighlightColor = Colors.grey.shade100;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// Builds a single placeholder box with the animated shimmer gradient.
  Widget _buildShimmerBox({required double height, double? width}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: _shimmerBaseColor,
            gradient: LinearGradient(
              colors: [
                _shimmerBaseColor,
                _shimmerHighlightColor,
                _shimmerBaseColor,
              ],
              stops: const [
                0.4,
                0.5,
                0.6,
              ], // A tighter, faster-moving shimmer band
              transform: _SlideGradientTransform(
                slidePercent: _shimmerController.value,
                patternWidth: 0.5,
              ),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }

  /// Builds a row that mimics the DataTable header.
  Widget _buildPlaceholderHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Row(
        children: [
          Expanded(flex: 4, child: _buildShimmerBox(height: 14)),
          const SizedBox(width: 20),
          Expanded(flex: 1, child: _buildShimmerBox(height: 14)),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: _buildShimmerBox(height: 14)),
          const SizedBox(width: 20),
          Expanded(flex: 1, child: _buildShimmerBox(height: 14)),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: _buildShimmerBox(height: 14)),
        ],
      ),
    );
  }

  /// Builds a row that mimics a single student data row in the DataTable.
  Widget _buildPlaceholderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Row(
        children: [
          // Placeholder for Student Name
          Expanded(flex: 4, child: _buildShimmerBox(height: 20)),
          const SizedBox(width: 20),
          // Placeholder for P/A Checkbox
          _buildShimmerBox(height: 24, width: 24),
          const SizedBox(width: 20),
          // Placeholder for GPS Distance
          Expanded(flex: 2, child: _buildShimmerBox(height: 20)),
          const SizedBox(width: 20),
          // Placeholder for NCC
          Expanded(flex: 1, child: _buildShimmerBox(height: 20)),
          const SizedBox(width: 20),
          // Placeholder for Magnitude
          Expanded(flex: 2, child: _buildShimmerBox(height: 20)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildPlaceholderHeader(),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: 8, // Display 8 placeholder rows
            itemBuilder: (context, index) => _buildPlaceholderRow(),
          ),
        ),
      ],
    );
  }
}

class RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const RotatingIcon({super.key, required this.icon, this.color = Colors.black});

  @override
  State<RotatingIcon> createState() => _RotatingIconState();
}

// rotating icon for loading
class _RotatingIconState extends State<RotatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(); // This makes it spin forever
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: 40, color: widget.color),
    );
  }
}
