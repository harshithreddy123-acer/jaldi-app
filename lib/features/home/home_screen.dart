import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/role_provider.dart';
import '../request/history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeLandingPage(),
    const HistoryScreenWrapper(),
    const ProfileRedirect(),
  ];

  @override
  Widget build(BuildContext context) {
    final userRole = ref.watch(userRoleProvider);

    if (userRole == UserRole.provider) {
      return const ProviderRedirectWidget();
    }

    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.orange.shade800,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomeLandingPage extends StatelessWidget {
  const HomeLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaldi'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            // Active Request Banner
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client.auth.currentUser != null
                  ? Supabase.instance.client
                      .from('service_requests')
                      .stream(primaryKey: ['id'])
                      .eq('customer_id', Supabase.instance.client.auth.currentUser!.id)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final active = (snapshot.data ?? []).where((r) =>
                    ['searching', 'assigned', 'accepted', 'in_progress']
                        .contains(r['status'])).toList();

                if (active.isEmpty) return const SizedBox.shrink();
                final req = active.first;
                final isAccepted =
                    req['status'] == 'accepted' || req['status'] == 'in_progress';
                final service = req['service_type'] ?? 'Roadside Assistance';

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isAccepted ? Colors.green.shade50 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAccepted ? Colors.green.shade400 : Colors.amber.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isAccepted ? Icons.check_circle : Icons.hourglass_top,
                              color: isAccepted ? Colors.green.shade800 : Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAccepted ? '🎉 Technician En Route!' : '🔍 Searching for Technician',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isAccepted ? Colors.green.shade900 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isAccepted
                              ? 'A verified technician accepted your $service request.'
                              : 'Searching for nearby highway patrol mechanics...',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/home/track'),
                            icon: const Icon(Icons.navigation, size: 18),
                            label: Text(isAccepted ? '🧭 Track Technician' : '📍 View Map'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isAccepted ? Colors.green.shade700 : Colors.amber.shade900,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Icon(Icons.car_repair, size: 80, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'Roadside Assistance',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Immediate help, live tracking, and emergency support.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            // Emergency Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/home/panic'),
                icon: const Icon(Icons.emergency, color: Colors.white),
                label: const Text(
                  'CRITICAL EMERGENCY / PANIC',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Request Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/home/request'),
                icon: const Icon(Icons.build_circle),
                label: const Text('Request Roadside Assistance', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Helplines
            OutlinedButton.icon(
              onPressed: () => context.push('/home/fallback'),
              icon: const Icon(Icons.phone_in_talk, color: Colors.green),
              label: const Text('Highway Helplines & Directory'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryScreenWrapper extends StatelessWidget {
  const HistoryScreenWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // We reuse the HistoryScreen but wrap it in a Scaffold since it's now a tab
    return const HistoryScreen();
  }
}

class ProfileRedirect extends StatelessWidget {
  const ProfileRedirect({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.push('/home/profile');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class ProviderRedirectWidget extends StatelessWidget {
  const ProviderRedirectWidget({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/provider');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
