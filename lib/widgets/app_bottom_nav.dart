import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../screens/chat_screen.dart';
import '../screens/device_scan_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final isBleConnected = context.select<AppState, bool>(
      (s) => s.isBleConnected,
    );

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => _onTabTapped(context, index),
      animationDuration: const Duration(milliseconds: 250),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 70,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: isBleConnected,
            backgroundColor: Colors.green,
            child: const Icon(Icons.bluetooth_rounded),
          ),
          selectedIcon: Badge(
            isLabelVisible: isBleConnected,
            backgroundColor: Colors.green,
            child: const Icon(Icons.bluetooth_connected_rounded),
          ),
          label: 'Devices',
        ),
        const NavigationDestination(
          icon: Icon(Icons.history_rounded),
          selectedIcon: Icon(Icons.history_rounded),
          label: 'History',
        ),
        const NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: 'AI Chat',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }

  void _onTabTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    final page = switch (index) {
      0 => const HomeScreen(),
      1 => const DeviceScanScreen(),
      2 => const HistoryScreen(),
      3 => const ChatScreen(),
      4 => const ProfileScreen(),
      _ => const HomeScreen(),
    };

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 180),
      ),
    );
  }
}
