import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Upper-cases and drops spaces and dashes, so "abc-123" finds "ABC 123".
String _normalizePlate(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// Whether gate log [data] matches the owner's search [query]: part of the
/// plate, the staff member's name, or the start of the ticket number.
bool spActivityMatchesQuery(
  Map<String, dynamic> data,
  String query, [
  Map<String, String>? staffNames,
]) {
  final String q = query.trim();
  if (q.isEmpty) return true;
  final String plate = (data['vehiclePlate'] as String?) ?? '';
  if (_normalizePlate(plate).contains(_normalizePlate(q))) return true;
  final String staff = spLogStaffName(data, staffNames) ?? '';
  if (staff.toLowerCase().contains(q.toLowerCase())) return true;
  final String ticket = ((data['transactionId'] as String?) ?? '').trim();
  return ticket.isNotEmpty && ticket.toLowerCase().startsWith(q.toLowerCase());
}

enum _OptionKind { plate, staff }

class _SearchOption {
  const _SearchOption(this.kind, this.id, this.label, this.count);

  final _OptionKind kind;

  /// The plate as scanned, or the staff uid.
  final String id;
  final String label;

  /// Scans in the loaded logs.
  final int count;
}

/// Search box for the owner's gate activity with a dropdown of suggestions:
/// the plates scanned that day and the facility's staff, each with how many
/// scans they have. Typing filters the list as you go; picking a plate fills
/// it in, picking a staff member filters to their scans. With the box empty
/// the dropdown lists every staff member, so it also works as the staff
/// picker.
class SpActivitySearch extends StatefulWidget {
  const SpActivitySearch({
    super.key,
    required this.logs,
    required this.staff,
    required this.query,
    required this.onQueryChanged,
    required this.staffFilter,
    required this.onStaffFilterChanged,
  });

  /// The logs being searched (the picked day plus vehicles still inside).
  final List<Map<String, dynamic>> logs;

  /// (uid, name) of everyone who can be filtered on, removed staff included.
  final List<(String, String)> staff;

  final String query;
  final ValueChanged<String> onQueryChanged;

  /// Staff uid the list is filtered to; null for everyone.
  final String? staffFilter;
  final ValueChanged<String?> onStaffFilterChanged;

  @override
  State<SpActivitySearch> createState() => _SpActivitySearchState();
}

class _SpActivitySearchState extends State<SpActivitySearch> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(SpActivitySearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) _controller.text = widget.query;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_SearchOption> _options(String text) {
    final String q = text.trim();
    final Map<String, int> staffCounts = <String, int>{};
    final Map<String, (String, int)> plates = <String, (String, int)>{};
    for (final Map<String, dynamic> log in widget.logs) {
      final String staffId = ((log['staffId'] as String?) ?? '').trim();
      if (staffId.isNotEmpty) {
        staffCounts[staffId] = (staffCounts[staffId] ?? 0) + 1;
      }
      final String plate = ((log['vehiclePlate'] as String?) ?? '').trim();
      final String key = _normalizePlate(plate);
      if (key.isEmpty || key == 'WALKIN' || key == 'UNREADABLE') continue;
      final (String, int)? seen = plates[key];
      plates[key] = (seen?.$1 ?? plate.toUpperCase(), (seen?.$2 ?? 0) + 1);
    }

    final List<_SearchOption> plateOptions = <_SearchOption>[
      for (final MapEntry<String, (String, int)> e in plates.entries)
        if (q.isNotEmpty && e.key.contains(_normalizePlate(q)))
          _SearchOption(_OptionKind.plate, e.value.$1, e.value.$1, e.value.$2),
    ]..sort((_SearchOption a, _SearchOption b) => b.count.compareTo(a.count));
    final List<_SearchOption> staffOptions = <_SearchOption>[
      for (final (String id, String name) in widget.staff)
        if (q.isEmpty || name.toLowerCase().contains(q.toLowerCase()))
          _SearchOption(_OptionKind.staff, id, name, staffCounts[id] ?? 0),
    ];
    return <_SearchOption>[...plateOptions.take(6), ...staffOptions];
  }

  void _select(_SearchOption option) {
    if (option.kind == _OptionKind.plate) {
      widget.onQueryChanged(option.id);
    } else {
      widget.onQueryChanged('');
      widget.onStaffFilterChanged(option.id);
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    String? staffLabel;
    for (final (String id, String name) in widget.staff) {
      if (id == widget.staffFilter) staffLabel = name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return RawAutocomplete<_SearchOption>(
              textEditingController: _controller,
              focusNode: _focusNode,
              optionsBuilder: (TextEditingValue value) => _options(value.text),
              displayStringForOption: (_SearchOption option) =>
                  option.kind == _OptionKind.plate ? option.id : '',
              onSelected: _select,
              fieldViewBuilder: _field,
              optionsViewBuilder: (context, onSelected, options) => _dropdown(
                context,
                onSelected,
                options.toList(),
                constraints.maxWidth,
              ),
            );
          },
        ),
        if (widget.staffFilter != null) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: Icon(
                Icons.badge_outlined,
                size: 16,
                color: AppTheme.accentText,
              ),
              label: Text(
                'Scanned by ${staffLabel ?? 'selected staff'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              backgroundColor: AppTheme.warningSoft,
              side: BorderSide(color: AppTheme.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              deleteIconColor: AppTheme.textMuted,
              onDeleted: () => widget.onStaffFilterChanged(null),
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    VoidCallback onFieldSubmitted,
  ) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onChanged: widget.onQueryChanged,
          onSubmitted: (_) => focusNode.unfocus(),
          decoration: InputDecoration(
            hintText: 'Search plate, staff or ticket #',
            isDense: true,
            filled: true,
            fillColor: AppTheme.surface,
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: AppTheme.textMuted,
            ),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      widget.onQueryChanged('');
                    },
                  )
                : IconButton(
                    tooltip: 'Show suggestions',
                    icon: const Icon(Icons.expand_more_rounded),
                    onPressed: () => focusNode.hasFocus
                        ? focusNode.unfocus()
                        : focusNode.requestFocus(),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(color: spCardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(
                color: value.text.isEmpty ? spCardBorder : AppTheme.accent,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
            ),
          ),
        );
      },
    );
  }

  Widget _dropdown(
    BuildContext context,
    AutocompleteOnSelected<_SearchOption> onSelected,
    List<_SearchOption> options,
    double width,
  ) {
    final int highlighted = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          elevation: 6,
          color: AppTheme.surface,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 300, maxWidth: width),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (BuildContext context, int index) {
                final _SearchOption option = options[index];
                final bool newSection =
                    index == 0 || options[index - 1].kind != option.kind;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (newSection) _sectionHeader(option.kind, index == 0),
                    _optionRow(
                      option,
                      highlighted: index == highlighted,
                      onTap: () => onSelected(option),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(_OptionKind kind, bool first) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, first ? 4 : 10, 14, 4),
      child: Text(
        kind == _OptionKind.plate ? 'PLATES' : 'STAFF',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _optionRow(
    _SearchOption option, {
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    final bool plate = option.kind == _OptionKind.plate;
    final bool selected = !plate && option.id == widget.staffFilter;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: highlighted ? AppTheme.surfaceAlt : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(
              plate ? Icons.directions_car_rounded : Icons.badge_outlined,
              size: 18,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: plate
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: SpPlateBadge(plate: option.label),
                    )
                  : Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              '${option.count} scan${option.count == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            if (selected) ...<Widget>[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 18, color: spEntryColor),
            ],
          ],
        ),
      ),
    );
  }
}
