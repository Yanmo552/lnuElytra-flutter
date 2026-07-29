import 'package:flutter/material.dart';

import 'auto_grab/auto_grab_tab.dart';
import 'manual_grab/manual_grab_tab.dart';

/// Main course-grabbing workspace with auto-grab and manual-grab tabs.
class GrabWorkspace extends StatelessWidget {
  const GrabWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: const TabBar(
              tabs: [
                Tab(text: '自动抢课'),
                Tab(text: '手动抢课'),
              ],
            ),
          ),

          // Tab views
          const Expanded(
            child: TabBarView(children: [AutoGrabTab(), ManualGrabTab()]),
          ),
        ],
      ),
    );
  }
}
