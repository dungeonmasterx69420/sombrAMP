import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

class FinampSettingsDropdown<T> extends StatelessWidget {
  const FinampSettingsDropdown({
    super.key,
    required this.dropdownItems,
    required this.selectedValue,
    required this.onSelected,
    this.selectedIcon,
  });

  final List<DropdownMenuEntry<T>> dropdownItems;
  final T? selectedValue;
  final IconData? selectedIcon;
  final void Function(T?) onSelected;

  @override
  Widget build(BuildContext context) {
    final defaultEntryStyle = ButtonStyle(
      padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu<T>(
          width: constraints.maxWidth,
          dropdownMenuEntries: dropdownItems
              .map(
                (e) => DropdownMenuEntry<T>(
                  value: e.value,
                  label: e.label,
                  leadingIcon: e.leadingIcon,
                  trailingIcon: e.trailingIcon,
                  enabled: e.enabled,
                  style: e.style ?? defaultEntryStyle,
                ),
              )
              .toList(),
          initialSelection: selectedValue,
          enableFilter: false,
          enableSearch: false,
          requestFocusOnTap: false,
          onSelected: onSelected,
          textStyle: Theme.of(context).textTheme.bodyMedium,
          leadingIcon: selectedIcon != null ? Icon(selectedIcon) : null,
          trailingIcon: const Icon(TablerIcons.chevron_down),
          selectedTrailingIcon: const Icon(TablerIcons.chevron_up),
          // System S: a field with an ink edge that opens a drop menu.
          menuStyle: Theme.of(context).menuTheme.style,
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            visualDensity: const VisualDensity(horizontal: -4.0, vertical: -4.0),
            isDense: true,
            contentPadding: const EdgeInsets.only(left: 12.0),
          ),
        );
      },
    );
  }
}
