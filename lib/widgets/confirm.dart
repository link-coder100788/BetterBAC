import 'package:flutter/material.dart';

import '../theme.dart';
import 'chunky.dart';

/// Asks a yes/no question. Resolves to true only if the user confirms.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: ChunkyButton.outlined(
                label: 'Cancel',
                textColor: Palette.muted,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChunkyButton(
                label: action,
                color: Palette.red,
                lipColor: Palette.redLip,
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}
