import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class SearchableDropdown<T> extends StatefulWidget {
  final List<T> items;
  final T? value;
  final String label;
  final String hint;
  final String Function(T) itemTitle;
  final ValueChanged<T?> onChanged;
  final bool Function(T, String) searchMatcher;

  const SearchableDropdown({
    super.key,
    required this.items,
    this.value,
    required this.label,
    required this.hint,
    required this.itemTitle,
    required this.onChanged,
    required this.searchMatcher,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => _SearchDialog<T>(
        items: widget.items,
        initialValue: widget.value,
        title: widget.label,
        itemTitle: widget.itemTitle,
        searchMatcher: widget.searchMatcher,
      ),
    ).then((selected) {
      if (selected != null || selected == null) {
        // Handle null if needed, but usually we want to keep selection if cancelled
        if (mounted && selected != widget.value) {
          widget.onChanged(selected);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: _showSearchDialog,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          filled: true,
          fillColor: isDark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          widget.value != null
              ? widget.itemTitle(widget.value as T)
              : widget.hint,
          style: TextStyle(
            color: widget.value != null
                ? theme.textTheme.bodyLarge?.color
                : theme.hintColor,
          ),
        ),
      ),
    );
  }
}

class _SearchDialog<T> extends StatefulWidget {
  final List<T> items;
  final T? initialValue;
  final String title;
  final String Function(T) itemTitle;
  final bool Function(T, String) searchMatcher;

  const _SearchDialog({
    required this.items,
    this.initialValue,
    required this.title,
    required this.itemTitle,
    required this.searchMatcher,
  });

  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  final _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items
            .where((item) => widget.searchMatcher(item, query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ابحث هنا...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final isSelected = item == widget.initialValue;
                  return ListTile(
                    title: Text(widget.itemTitle(item)),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(context, item),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tileColor: isSelected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }
}
