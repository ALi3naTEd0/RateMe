import 'package:flutter/material.dart';

class DominantColorPicker extends StatelessWidget {
  final List<Color> colors;
  final Color? selected;
  final Function(Color?) onSelect; // Changed to accept nullable Color

  const DominantColorPicker({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8.0,
      children: colors.map((color) {
        final isSelected = selected == color;
        return GestureDetector(
          onTap: () {
            // Toggle behavior: if already selected, deselect it
            if (isSelected) {
              onSelect(null); // Pass null to deselect
            } else {
              onSelect(color);
            }
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Colors.white
                    : Colors.grey.withValues(alpha: 0.5),
                width: isSelected ? 3.0 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
                if (isSelected)
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 0),
                  ),
              ],
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}
