import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../dictation.dart';
import '../src/rust/api/dictation.dart';
import '../theme.dart';
import 'coach_panel.dart' show ShimmerText;

enum _Phase { idle, preparing, listening, transcribing }

/// "Dictate" → listen → tap Stop → text is inserted at the cursor of
/// [controller]. Whisper runs on-device in Rust; audio never leaves the phone.
class DictationBar extends StatefulWidget {
  const DictationBar({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<DictationBar> createState() => _DictationBarState();
}

class _DictationBarState extends State<DictationBar>
    with SingleTickerProviderStateMixin {
  static const _sampleRate = 16000;
  static const _maxListen = Duration(minutes: 5);

  _Phase _phase = _Phase.idle;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audio;
  final _buffer = BytesBuilder(copy: false);
  final _elapsed = Stopwatch();
  Timer? _ticker;
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    // Load the model in the background so the first tap is quick.
    Dictation.prepare().catchError((_) {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _audio?.cancel();
    _recorder?.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.preparing);
    try {
      await Dictation.prepare();
    } on DictationModelMissing {
      _snack("Dictation isn't available in this build.");
      return setState(() => _phase = _Phase.idle);
    } catch (e) {
      _snack(errorMessage(e));
      return setState(() => _phase = _Phase.idle);
    }

    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      _snack('Allow microphone access for BetterBAC in your device settings.');
      return setState(() => _phase = _Phase.idle);
    }
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _buffer.clear();
    _audio = stream.listen(_buffer.add);
    _elapsed
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_elapsed.elapsed >= _maxListen) {
        _stop();
      } else {
        setState(() {});
      }
    });
    _pulse.repeat(reverse: true);
    if (mounted) setState(() => _phase = _Phase.listening);
  }

  Future<void> _stop() async {
    if (_phase != _Phase.listening) return;
    _ticker?.cancel();
    _pulse.stop();
    _elapsed.stop();
    await _recorder?.stop();
    await _audio?.cancel();
    _audio = null;
    if (!mounted) return;
    setState(() => _phase = _Phase.transcribing);

    final bytes = _buffer.takeBytes();
    // 16-bit little-endian PCM. Copy if the buffer isn't 2-byte aligned.
    final aligned = bytes.offsetInBytes.isEven ? bytes : Uint8List.fromList(bytes);
    final samples = aligned.buffer.asInt16List(
      aligned.offsetInBytes,
      aligned.lengthInBytes ~/ 2,
    );
    final result = await guard(
      context,
      () => transcribe(samples: samples, sampleRate: _sampleRate),
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    if (result == null) return;
    if (result.text.trim().isEmpty) {
      _snack("Didn't catch that. Try again a little closer to the mic.");
    } else {
      _insert(result.text.trim());
    }
  }

  /// Inserts at the cursor (or the end), with a space if needed.
  void _insert(String text) {
    final c = widget.controller;
    final at = c.selection.isValid ? c.selection.end : c.text.length;
    final before = c.text.substring(0, at);
    final spaced = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? text : ' $text';
    c.value = TextEditingValue(
      text: before + spaced + c.text.substring(at),
      selection: TextSelection.collapsed(offset: at + spaced.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Dictation.supported) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_phase) {
        _Phase.idle => _pill(
          key: const ValueKey('idle'),
          icon: Icons.mic_rounded,
          label: 'Dictate',
          color: Palette.blue,
          onTap: _start,
        ),
        _Phase.preparing => const Row(
          key: ValueKey('preparing'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Getting ready…', style: TextStyle(color: Palette.muted)),
          ],
        ),
        _Phase.listening => Row(
          key: const ValueKey('listening'),
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
              child: const Icon(Icons.circle, color: Palette.red, size: 14),
            ),
            const SizedBox(width: 6),
            Text(
              'Listening ${_format(_elapsed.elapsed)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Palette.red),
            ),
            const SizedBox(width: 10),
            _pill(
              icon: Icons.stop_rounded,
              label: 'Stop',
              color: Palette.red,
              onTap: _stop,
            ),
          ],
        ),
        _Phase.transcribing => const ShimmerText(
          'Turning speech into text…',
          key: ValueKey('transcribing'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      },
    );
  }

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _pill({
    Key? key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.1), Palette.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
