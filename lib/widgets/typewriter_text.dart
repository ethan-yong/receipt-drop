import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Types [text] out character-by-character with a blinking caret, then holds
/// the finished sentence. Restarts from scratch whenever [text] changes (a
/// new insight replacing the one this card showed).
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.startDelay = Duration.zero,
    this.minStepDelayMs = 60,
    this.maxStepDelayMs = 100,
  });

  final String text;
  final TextStyle? style;
  final Duration startDelay;
  final int minStepDelayMs;
  final int maxStepDelayMs;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  final _random = Random();
  Timer? _timer;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _shown = 0;
    Future.delayed(widget.startDelay, () {
      if (mounted) _step();
    });
  }

  void _step() {
    if (_shown >= widget.text.length) return;
    final stepSpan = max(1, widget.maxStepDelayMs - widget.minStepDelayMs);
    _timer = Timer(
      Duration(milliseconds: widget.minStepDelayMs + _random.nextInt(stepSpan)),
      () {
      if (!mounted) return;
      setState(() {
        _shown = min(_shown + 1, widget.text.length);
      });
      _step();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _shown >= widget.text.length;
    return RichText(
      text: TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: widget.text.substring(0, _shown)),
          if (!done) const TextSpan(text: '▍'),
        ],
      ),
    );
  }
}
