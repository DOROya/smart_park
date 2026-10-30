import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The reasons picked so far, in order, skipping dropdowns left empty.
List<String> spPickedReasons(List<String?> values) =>
    values.whereType<String>().toList();

/// One or more reasons picked from [options], one dropdown each. "+ Add
/// Another Reason" adds a dropdown that offers only the reasons not picked
/// yet; every dropdown after the first can be removed again.
class SpReasonDropdowns extends StatelessWidget {
  const SpReasonDropdowns({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.missing = false,
    this.enabled = true,
  });

  final List<String> options;

  /// One entry per dropdown (null while unpicked); at least one.
  final List<String?> values;
  final ValueChanged<List<String?>> onChanged;

  /// The form was sent without a reason: outline the empty dropdowns.
  final bool missing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final List<String?> rows = values.isEmpty ? <String?>[null] : values;
    final List<String> picked = spPickedReasons(rows);
    final bool canAdd =
        enabled &&
        !rows.contains(null) &&
        options.any((String o) => !picked.contains(o));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: [
                Expanded(child: _dropdown(rows, i)),
                if (i > 0)
                  IconButton(
                    tooltip: 'Remove this reason',
                    onPressed: enabled
                        ? () => onChanged(<String?>[...rows]..removeAt(i))
                        : null,
                    icon: Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
        if (canAdd)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: () => onChanged(<String?>[...rows, null]),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add Another Reason',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentText,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dropdown(List<String?> rows, int index) {
    final String? value = rows[index];
    // Reasons picked in the other dropdowns can't be picked twice.
    final List<String> choices = <String>[
      for (final String option in options)
        if (option == value || !rows.contains(option)) option,
    ];
    final bool empty = value == null;
    return InputDecorator(
      isEmpty: empty,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppTheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          borderSide: BorderSide(
            color: missing && empty ? AppTheme.dangerBorder : AppTheme.border,
          ),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            index == 0 ? 'Select a reason' : 'Select another reason',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
          dropdownColor: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          items: <DropdownMenuItem<String>>[
            for (final String choice in choices)
              DropdownMenuItem<String>(value: choice, child: Text(choice)),
          ],
          onChanged: enabled
              ? (String? picked) =>
                    onChanged(<String?>[...rows]..[index] = picked)
              : null,
        ),
      ),
    );
  }
}
