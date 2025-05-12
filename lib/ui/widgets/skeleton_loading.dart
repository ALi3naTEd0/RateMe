import 'package:flutter/material.dart';

/// A widget that displays a skeleton loading animation
class SkeletonLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoading({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 4,
  });

  @override
  State<SkeletonLoading> createState() => _SkeletonLoadingState();
}

class _SkeletonLoadingState extends State<SkeletonLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final color = Color.lerp(
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: (Theme.of(context).colorScheme.surfaceContainerHighest.a *
                      0.5)
                  .toDouble()),
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: (Theme.of(context).colorScheme.surfaceContainerHighest.a *
                      0.8)
                  .toDouble()),
          _animation.value,
        )!;

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// A skeleton placeholder for album cards
class AlbumCardSkeleton extends StatelessWidget {
  const AlbumCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rating box placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: (Theme.of(context).colorScheme.primary.a * 0.3)
                          .toDouble()),
                  width: 1,
                ),
              ),
              child: const Center(
                child: SkeletonLoading(
                  width: 30,
                  height: 24,
                  borderRadius: 4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Album artwork placeholder
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const SkeletonLoading(
                width: 48,
                height: 48,
                borderRadius: 0,
              ),
            ),
          ],
        ),
        title: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: SkeletonLoading(
            width: double.infinity,
            height: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: SkeletonLoading(
            width: MediaQuery.of(context).size.width * 0.4,
            height: 14,
          ),
        ),
        trailing: const Icon(Icons.drag_handle, color: Colors.transparent),
      ),
    );
  }
}

/// A skeleton placeholder for list cards
class ListCardSkeleton extends StatelessWidget {
  const ListCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
          vertical: 2, horizontal: 0), // Reduced from 4 to 2
      child: ListTile(
        dense: true, // Added to make it more compact
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 2), // Reduced from 4 to 2
        leading: Container(
          width: 42, // Reduced from 48 to 42
          height: 42, // Reduced from 48 to 42
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary.withValues(
                alpha: (Theme.of(context).colorScheme.secondary.a * 0.1)
                    .toDouble()),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.playlist_play,
            size: 32, // Reduced from 36 to 32
            color: Theme.of(context).colorScheme.secondary.withValues(
                alpha: (Theme.of(context).colorScheme.secondary.a * 0.3)
                    .toDouble()),
          ),
        ),
        title: const Padding(
          padding: EdgeInsets.only(top: 4), // Reduced from 8 to 4
          child: SkeletonLoading(
            width: double.infinity,
            height: 16,
          ),
        ),
        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 4, bottom: 4), // Reduced from 8 to 4
          child: Row(
            children: [
              SkeletonLoading(
                width: MediaQuery.of(context).size.width * 0.15,
                height: 14,
              ),
              const SizedBox(width: 8),
              const Text('|'),
              const SizedBox(width: 8),
              SkeletonLoading(
                width: MediaQuery.of(context).size.width * 0.3,
                height: 14,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.drag_handle, color: Colors.transparent),
      ),
    );
  }
}

/// A skeleton placeholder for platform buttons
class PlatformButtonSkeleton extends StatelessWidget {
  final double size;

  const PlatformButtonSkeleton({
    super.key,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonLoading(
      width: size,
      height: size,
      borderRadius: size / 2,
    );
  }
}
