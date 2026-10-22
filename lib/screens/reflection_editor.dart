import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../src/rust/api/cas.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/coach_panel.dart';
import '../widgets/confirm.dart';

/// Write or edit a reflection, then hand it to ManageBAC in one tap.
class ReflectionEditor extends StatefulWidget {
  const ReflectionEditor({super.key, this.reflectionId, this.experienceId});

  /// Existing reflection to edit; null to start a new one.
  final String? reflectionId;

  /// Pre-selected experience for a new reflection.
  final String? experienceId;

  @override
  State<ReflectionEditor> createState() => _ReflectionEditorState();
}

class _ReflectionEditorState extends State<ReflectionEditor> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String? _id = widget.reflectionId;
  late String? _experienceId = widget.experienceId;
  final Set<LearningOutcome> _outcomes = {};
  List<Experience> _experiences = [];
  DateTime? _exportedAt;
  int _words = 0;
  bool _loading = true;
  bool _dirty = false;
  bool _busy = false;
  bool _showPrompts = false;

  @override
  void initState() {
    super.initState();
    _load();
    _title.addListener(_markDirty);
    _body.addListener(() {
      _markDirty();
      setState(() => _words = countWords(text: _body.text));
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_loading && !_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    final experiences = await guard(context, listExperiences) ?? [];
    final id = _id;
    Reflection? existing;
    if (id != null && mounted) {
      existing = await guard(context, () => getReflection(id: id));
    }
    if (!mounted) return;
    setState(() {
      _experiences = experiences;
      if (existing != null) {
        _title.text = existing.title;
        _body.text = existing.body;
        _experienceId = existing.experienceId;
        _outcomes.addAll(existing.outcomes);
        _exportedAt = existing.exportedAt;
      }
      _loading = false;
    });
  }

  ReflectionDraft get _draft => ReflectionDraft(
    experienceId: _experienceId,
    title: _title.text,
    body: _body.text,
    outcomes: LearningOutcome.values.where(_outcomes.contains).toList(),
  );

  bool get _isEmpty =>
      _title.text.trim().isEmpty && _body.text.trim().isEmpty;

  /// Persists the reflection. Returns false if saving failed.
  Future<bool> _save({bool quiet = false}) async {
    final saved = await guard(
      context,
      () => saveReflection(id: _id, draft: _draft),
    );
    if (saved == null || !mounted) return false;
    setState(() {
      _id = saved.reflection.id;
      _dirty = false;
    });
    notifyDataChanged();
    if (!quiet) {
      showXp(context, saved.xpGained, message: 'Nice writing!');
      if (saved.xpGained == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
    }
    return true;
  }

  Future<void> _sendToManageBac() async {
    setState(() => _busy = true);
    try {
      if ((_dirty || _id == null) && !await _save(quiet: true)) return;
      if (!mounted) return;
      final export = await guard(context, () => exportReflection(id: _id!));
      if (export == null || !mounted) return;
      await Clipboard.setData(ClipboardData(text: export.text));
      setState(() => _exportedAt = DateTime.now());
      notifyDataChanged();

      final url = export.url;
      var opened = false;
      if (url != null) {
        opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
      if (!mounted) return;
      showXp(context, export.xpGained, message: 'Reflection sent!');
      await _showCopiedDialog(hasUrl: url != null, opened: opened);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCopiedDialog({required bool hasUrl, required bool opened}) {
    final String message;
    if (opened) {
      message = 'ManageBAC is opening. Add a new reflection there and paste.';
    } else if (hasUrl) {
      message = "We couldn't open your ManageBAC link. Open ManageBAC yourself and paste.";
    } else {
      message =
          'Add your ManageBAC CAS link in Profile → Settings and next time we '
          'will take you straight there. For now, open ManageBAC and paste.';
    }
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.content_paste_go_rounded,
          color: Palette.green,
          size: 56,
        ),
        title: const Text('Copied to clipboard!'),
        content: Text(message, textAlign: TextAlign.center),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          ChunkyButton(
            label: 'Got it',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final id = _id;
    if (id == null) return;
    final ok = await confirm(
      context,
      title: 'Delete reflection?',
      message: "This can't be undone.",
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    if (!await attempt(context, () => deleteReflection(id: id))) return;
    _dirty = false;
    notifyDataChanged();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: !_dirty || _isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Autosave on the way out so nothing is ever lost.
        final navigator = Navigator.of(context);
        if (await _save(quiet: true)) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_id == null ? 'New reflection' : 'Reflection'),
          actions: [
            if (_id != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_exportedAt != null) const _SentBanner(),
            _experiencePicker(),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SectionTitle('Learning outcomes'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in LearningOutcome.values)
                  Tooltip(
                    message: o.description(),
                    child: ChoiceTile(
                      label: 'LO${o.number()} · ${o.shortName()}',
                      color: Palette.green,
                      selected: _outcomes.contains(o),
                      onTap: () => setState(() {
                        _outcomes.contains(o) ? _outcomes.remove(o) : _outcomes.add(o);
                        _dirty = true;
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _promptsCard(),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              minLines: 10,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What happened? What did you learn? What will you do next?',
              ),
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text(
                '$_words words',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Palette.muted),
              ),
            ),
            const SizedBox(height: 16),
            CoachPanel(
              draft: () => _draft,
              wordCount: _words,
              tagged: _outcomes,
              onTag: (o) => setState(() {
                _outcomes.add(o);
                _dirty = true;
              }),
            ),
            const SizedBox(height: 24),
            ChunkyButton(
              label: 'Copy & open ManageBAC',
              icon: Icons.send_rounded,
              onPressed: _busy || _body.text.trim().isEmpty ? null : _sendToManageBac,
            ),
            const SizedBox(height: 12),
            ChunkyButton.outlined(
              label: 'Save draft',
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _experiencePicker() {
    // Guard against a stale id (e.g. experience deleted).
    final value = _experiences.any((e) => e.id == _experienceId)
        ? _experienceId
        : null;
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.flag_rounded),
        hintText: 'Link to an experience (optional)',
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('No experience')),
        for (final e in _experiences)
          DropdownMenuItem(value: e.id, child: Text(e.title, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (id) => setState(() {
        _experienceId = id;
        _dirty = true;
      }),
    );
  }

  Widget _promptsCard() {
    final prompts = reflectionPrompts(
      outcomes: LearningOutcome.values.where(_outcomes.contains).toList(),
    );
    return ChunkyCard(
      borderColor: Palette.blue.withValues(alpha: 0.4),
      color: Palette.blue.withValues(alpha: 0.06),
      onTap: () => setState(() => _showPrompts = !_showPrompts),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, color: Palette.blue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Need inspiration?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Palette.blueLip,
                  ),
                ),
              ),
              Icon(
                _showPrompts ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: Palette.blue,
              ),
            ],
          ),
          if (_showPrompts) ...[
            const SizedBox(height: 8),
            for (final p in prompts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('•  $p'),
              ),
          ],
        ],
      ),
    );
  }
}

class _SentBanner extends StatelessWidget {
  const _SentBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Palette.green),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sent to ManageBAC. Edits here won\'t update ManageBAC. Send again to copy the new text.',
              style: TextStyle(color: Palette.greenLip, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
