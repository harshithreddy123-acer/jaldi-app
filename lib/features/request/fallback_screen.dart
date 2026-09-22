import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FallbackScreen extends ConsumerStatefulWidget {
  const FallbackScreen({super.key});

  @override
  ConsumerState<FallbackScreen> createState() => _FallbackScreenState();
}

class _FallbackScreenState extends ConsumerState<FallbackScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _providers = [];

  final List<Map<String, String>> _emergencyHelplines = [
    {
      'title': 'National Highway Authority (NHAI)',
      'number': '1033',
      'desc': '24/7 Highway Emergency, Breakdown & Towing',
    },
    {
      'title': 'National Emergency Helpline',
      'number': '112',
      'desc': 'All-in-one Police, Fire & Medical rescue',
    },
    {
      'title': 'Highway Police Control Room',
      'number': '100',
      'desc': 'Direct Highway Police Dispatch',
    },
    {
      'title': 'Ambulance & Medical Emergency',
      'number': '108',
      'desc': 'Emergency Medical Services',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchApprovedProviders();
  }

  Future<void> _fetchApprovedProviders() async {
    try {
      final data = await Supabase.instance.client
          .from('provider_profiles')
          .select('id, bio, verification_status, profiles(full_name, phone), provider_details(vehicle_type, specialties)')
          .eq('verification_status', 'approved');

      setState(() {
        _providers = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error fetching providers: $e');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helplines & Mechanics'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '24/7 Highway Emergency Hotlines',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Instant toll-free telephone assistance if data or GPS is failing.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ..._emergencyHelplines.map((helpline) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade700,
                        child: const Icon(Icons.phone, color: Colors.white),
                      ),
                      title: Text(
                        helpline['title']!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${helpline['desc']}\nCall: ${helpline['number']}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.call, color: Colors.red),
                        onPressed: () => _makePhoneCall(helpline['number']!),
                      ),
                      onTap: () => _makePhoneCall(helpline['number']!),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                const Text(
                  'Verified Technicians Directory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_providers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No partner mechanics currently registered in this region.\nPlease use the 24/7 highway hotlines above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._providers.map((p) {
                    final profile = p['profiles'] as Map<String, dynamic>?;
                    final name = profile?['full_name'] ?? 'Verified Partner';
                    final phone = profile?['phone'] ?? '';
                    final details = p['provider_details'] as Map<String, dynamic>?;
                    final vehicle = details?['vehicle_type'] ?? 'Technician';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.build, color: Colors.white),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('$vehicle • ${phone.isNotEmpty ? phone : "Call via support"}'),
                        trailing: phone.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.phone, color: Colors.green),
                                onPressed: () => _makePhoneCall(phone),
                              )
                            : null,
                        onTap: phone.isNotEmpty ? () => _makePhoneCall(phone) : null,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
