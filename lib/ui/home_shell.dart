import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'record/record_page.dart';
import 'customer/customers_page.dart';
import 'settings/mine_page.dart';
import 'today/today_page.dart';

final class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: controller.tabIndex,
          children: const [
            RecordPage(),
            TodayPage(),
            CustomersPage(),
            MinePage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: controller.tabIndex,
        onDestinationSelected: controller.selectTab,
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.greenBackground,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 18,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.greenInk
                : AppColors.muted,
          ),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: '记一笔',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '流水',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '客户',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
