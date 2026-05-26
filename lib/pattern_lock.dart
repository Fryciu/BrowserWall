import 'package:flutter/material.dart';

class PatternLock extends StatefulWidget {
  final int size;
  final ValueChanged<List<int>> onPatternEntered;
  final String? errorText;

  const PatternLock({
    super.key,
    this.size = 3,
    required this.onPatternEntered,
    this.errorText,
  });

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> {
  List<int> _selected = [];
  Offset? _currentFinger;
  final Map<int, Offset> _dots = {};

  void _initDots(Size size) {
    if (_dots.isNotEmpty) return;
    final w = size.width;
    final h = size.height;
    final cellW = w / widget.size;
    final cellH = h / widget.size;
    for (int row = 0; row < widget.size; row++) {
      for (int col = 0; col < widget.size; col++) {
        final idx = row * widget.size + col;
        _dots[idx] = Offset(
          col * cellW + cellW / 2,
          row * cellH + cellH / 2,
        );
      }
    }
  }

  int? _hitTest(Offset pos) {
    for (final entry in _dots.entries) {
      if ((entry.value - pos).distance < 30) return entry.key;
    }
    return null;
  }

  void _onPanStart(DragStartDetails d) {
    final hit = _hitTest(d.localPosition);
    if (hit != null) {
      setState(() {
        _selected = [hit];
        _currentFinger = d.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_selected.isEmpty) return;
    final hit = _hitTest(d.localPosition);
    setState(() {
      _currentFinger = d.localPosition;
      if (hit != null && !_selected.contains(hit)) {
        _selected.add(hit);
      }
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_selected.length >= 2) {
      final pattern = List<int>.from(_selected);
      widget.onPatternEntered(pattern);
    }
    setState(() {
      _selected = [];
      _currentFinger = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _initDots(constraints.biggest);
            return GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                painter: _PatternPainter(
                  dots: _dots,
                  selected: _selected,
                  finger: _currentFinger,
                  size: widget.size,
                ),
                child: Stack(
                  children: _dots.entries.map((entry) {
                    final isSelected = _selected.contains(entry.key);
                    return Positioned(
                      left: entry.value.dx - 18,
                      top: entry.value.dy - 18,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Colors.blue.withValues(alpha: 0.3)
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey,
                            width: 2.5,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blue,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final Map<int, Offset> dots;
  final List<int> selected;
  final Offset? finger;
  final int size;

  _PatternPainter({
    required this.dots,
    required this.selected,
    this.finger,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (selected.isEmpty) return;
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(
        dots[selected[i]]!,
        dots[selected[i + 1]]!,
        paint,
      );
    }

    if (finger != null && selected.isNotEmpty) {
      canvas.drawLine(
        dots[selected.last]!,
        finger!,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.selected != selected || oldDelegate.finger != finger;
  }
}
