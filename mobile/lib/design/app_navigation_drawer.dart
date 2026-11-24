import 'package:flutter/material.dart';

import 'app_logo.dart';

class AppNavigationSection {
  const AppNavigationSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  NavigationDestination get destination => NavigationDestination(
    icon: Icon(icon),
    selectedIcon: Icon(selectedIcon),
    label: label,
  );
}

class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Abrir menu',
    icon: const Icon(Icons.menu),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}

class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({
    super.key,
    required this.username,
    required this.role,
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
  });

  final String username;
  final String role;
  final List<AppNavigationSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AbigailOvos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          username,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          role,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Navegação',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (var index = 0; index < sections.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListTile(
                  leading: Icon(
                    index == selectedIndex
                        ? sections[index].selectedIcon
                        : sections[index].icon,
                  ),
                  title: Text(sections[index].label),
                  selected: index == selectedIndex,
                  selectedTileColor: theme.colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(index);
                  },
                ),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.logout),
              title: const Text('Terminar sessão'),
              onTap: () {
                Navigator.of(context).pop();
                onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
