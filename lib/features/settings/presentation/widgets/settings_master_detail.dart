import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/responsive.dart';

class SettingsCategory {
  final IconData icon;
  final String title;
  final String subtitle;

  const SettingsCategory({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class SettingsMasterDetail extends StatelessWidget {
  final List<SettingsCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onCategorySelected;
  final IndexedWidgetBuilder contentBuilder;

  const SettingsMasterDetail({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.onCategorySelected,
    required this.contentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isWideScreen && !context.isTv) {
      return _buildWideLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return ListTile(
          leading: Icon(category.icon),
          title: Text(category.title),
          subtitle: Text(category.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            onCategorySelected(index);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _CategoryDetailPage(
                  title: category.title,
                  child: contentBuilder(context, index),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = index == selectedIndex;

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: ListTile(
                  leading: Icon(
                    category.icon,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : null,
                  ),
                  title: Text(
                    category.title,
                    style: isSelected
                        ? TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    category.subtitle,
                    style: isSelected
                        ? TextStyle(
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                          )
                        : null,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  onTap: () => onCategorySelected(index),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: contentBuilder(context, selectedIndex),
        ),
      ],
    );
  }
}

class _CategoryDetailPage extends StatelessWidget {
  final String title;
  final Widget child;

  const _CategoryDetailPage({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}
