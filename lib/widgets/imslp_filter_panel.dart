import 'package:flutter/material.dart';

import '../models/imslp_models.dart';

class ImslpFilterPanel extends StatelessWidget {
  final WorkFilters filters;
  final ValueChanged<WorkFilters> onChanged;
  final List<String> availableStyles;
  final List<String> availableLanguages;
  final List<String> availableKeys;

  const ImslpFilterPanel({
    super.key,
    required this.filters,
    required this.onChanged,
    this.availableStyles = const [],
    this.availableLanguages = const [],
    this.availableKeys = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Icon(
            Icons.tune,
            color: filters.isEmpty ? Colors.white54 : Colors.lightBlueAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Filtres',
            style: TextStyle(
              color: filters.isEmpty ? Colors.white54 : Colors.lightBlueAccent,
              fontSize: 14,
            ),
          ),
          if (!filters.isEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onChanged(const WorkFilters()),
              child: const Icon(Icons.clear, color: Colors.white38, size: 16),
            ),
          ],
        ],
      ),
      collapsedIconColor: Colors.white38,
      iconColor: Colors.white54,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                label: 'Instrumentation',
                hint: 'ex: 2vn va vc, fl pf, str...',
                value: filters.instrumentation,
                onChanged: (v) =>
                    onChanged(filters.copyWith(instrumentation: v)),
              ),
              const SizedBox(height: 8),
              if (availableStyles.isNotEmpty)
                _buildDropdown(
                  label: 'Style',
                  value:
                      filters.style.isEmpty ? null : filters.style,
                  items: availableStyles,
                  onChanged: (v) =>
                      onChanged(filters.copyWith(style: v ?? '')),
                ),
              if (availableStyles.isNotEmpty) const SizedBox(height: 8),
              _buildTextField(
                label: 'Genre',
                hint: 'ex: Sonatas, Concertos...',
                value: filters.genre,
                onChanged: (v) => onChanged(filters.copyWith(genre: v)),
              ),
              const SizedBox(height: 8),
              if (availableKeys.isNotEmpty)
                _buildDropdown(
                  label: 'Tonalité',
                  value: filters.key.isEmpty ? null : filters.key,
                  items: availableKeys,
                  onChanged: (v) =>
                      onChanged(filters.copyWith(key: v ?? '')),
                ),
              if (availableKeys.isNotEmpty) const SizedBox(height: 8),
              if (availableLanguages.isNotEmpty)
                _buildDropdown(
                  label: 'Langue',
                  value: filters.language.isEmpty
                      ? null
                      : filters.language,
                  items: availableLanguages,
                  onChanged: (v) =>
                      onChanged(filters.copyWith(language: v ?? '')),
                ),
              if (availableLanguages.isNotEmpty) const SizedBox(height: 8),
              _buildYearRange(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: !filters.includeManuscripts,
                    onChanged: (v) => onChanged(
                        filters.copyWith(includeManuscripts: !(v ?? false))),
                    activeColor: Colors.lightBlueAccent,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  const Text('Exclure les manuscrits',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: TextEditingController(text: value),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: Colors.grey[850],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Tous')),
        ...items.map((s) => DropdownMenuItem(value: s, child: Text(s))),
      ],
      onChanged: (v) => onChanged(v == '' ? null : v),
    );
  }

  Widget _buildYearRange() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(
              text: filters.yearFrom?.toString() ?? '',
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Année min',
              labelStyle:
                  const TextStyle(color: Colors.white54, fontSize: 12),
              hintText: '1600',
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 12),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.grey[850],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              final year = int.tryParse(v);
              onChanged(year != null
                  ? filters.copyWith(yearFrom: year)
                  : filters.copyWith(clearYearFrom: true));
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('–', style: TextStyle(color: Colors.white38)),
        ),
        Expanded(
          child: TextField(
            controller: TextEditingController(
              text: filters.yearTo?.toString() ?? '',
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Année max',
              labelStyle:
                  const TextStyle(color: Colors.white54, fontSize: 12),
              hintText: '1900',
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 12),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.grey[850],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              final year = int.tryParse(v);
              onChanged(year != null
                  ? filters.copyWith(yearTo: year)
                  : filters.copyWith(clearYearTo: true));
            },
          ),
        ),
      ],
    );
  }
}
