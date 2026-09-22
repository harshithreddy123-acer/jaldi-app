import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/notification_service.dart';
import 'incoming_request_screen.dart';
import 'technician_navigation_screen.dart';

class ProviderDashboard extends ConsumerStatefulWidget {
  const ProviderDashboard({super.key});

  @override
  ConsumerState<ProviderDashboard> createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends ConsumerState<ProviderDashboard> {
  bool _isOnline = false;
  bool _isUpdating = false;
  bool _isApproved = false;
  bool _isLoadingApproval = true;
  StreamSubscription<RemoteMessage>? _jobAlertSub;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
    _listenToPushJobAlerts();
  }

  @override
  void dispose() {
    _jobAlertSub?.cancel();
    super.dispose();
  }

  void _listenToPushJobAlerts() {
    _jobAlertSub = NotificationService.instance.onJobAlert.listen((message) {
      final requestId = message.data['request_id']?.toString() ??
          message.data['requestId']?.toString() ??
          message.data['id']?.toString();
      if (requestId != null && mounted) {
        _showIncomingJobPopup(
          requestId: requestId,
          title: message.notification?.title ?? '🚨 Urgent Roadside Assistance Alert',
          body: message.notification?.body ?? 'A nearby driver needs assistance.',
        );
      }
    });
  }

  void _showIncomingJobPopup({
    required String requestId,
    required String title,
    required String body,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.emergency, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.timer, size: 16, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Instant Dispatch: View and accept before another technician does!',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IncomingRequestScreen(requestId: requestId),
                ),
              );
            },
            icon: const Icon(Icons.flash_on),
            label: const Text('View & Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateAsTechnician({bool andGoOnline = true}) async {
    setState(() => _isUpdating = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Please sign in first.';

      try {
        await Supabase.instance.client.rpc('self_approve_technician');
      } catch (_) {
        // Fallback direct updates if RPC is not installed yet
        await Supabase.instance.client
            .from('profiles')
            .update({'role': 'provider'}).eq('id', user.id);
        await Supabase.instance.client.from('provider_profiles').upsert({
          'id': user.id,
          'verification_status': 'approved',
          'bio': 'Certified Highway Technician',
        });
        await Supabase.instance.client.from('provider_details').upsert({
          'user_id': user.id,
          'vehicle_type': 'Mobile Service Van',
          'is_online': andGoOnline,
        });
      }

      if (andGoOnline) {
        await NotificationService.instance.syncTokenWithSupabase();
      }

      await _checkCurrentStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Technician profile successfully activated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showActivationHelpDialog(e.toString());
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingApproval = false);
        return;
      }

      final profileData = await Supabase.instance.client
          .from('provider_profiles')
          .select('verification_status')
          .eq('id', user.id)
          .maybeSingle();

      final approved =
          profileData != null && profileData['verification_status'] == 'approved';

      bool online = false;
      if (approved) {
        final detailsData = await Supabase.instance.client
            .from('provider_details')
            .select('is_online')
            .eq('user_id', user.id)
            .maybeSingle();
        online = detailsData?['is_online'] as bool? ?? false;
      }

      if (mounted) {
        setState(() {
          _isApproved = approved;
          _isOnline = online;
          _isLoadingApproval = false;
        });
      }
    } catch (e) {
      debugPrint('Status check error: $e');
      if (mounted) setState(() => _isLoadingApproval = false);
    }
  }


  void _showActivationHelpDialog(String error) {
    const sqlCode = '''-- 1. Enable Realtime
alter publication supabase_realtime add table public.provider_locations, public.service_requests;

-- 2. Allow technicians to manage their profile
create policy "providers manage own profile" on public.provider_profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- 3. 1-Click self approval function
create or replace function public.self_approve_technician()
returns text language plpgsql security definer as \$\$
begin
  update public.profiles set role = 'provider' where id = auth.uid();
  insert into public.provider_profiles (id, verification_status, bio)
  values (auth.uid(), 'approved', 'Certified Highway Technician')
  on conflict (id) do update set verification_status = 'approved';
  insert into public.provider_details (user_id, vehicle_type, is_online)
  values (auth.uid(), 'Mobile Service Van', false)
  on conflict (user_id) do update set vehicle_type = 'Mobile Service Van';
  return 'Approved';
end;
\$\$;
grant execute on function public.self_approve_technician() to authenticated, service_role;''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.terminal, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Database Setup Needed', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supabase rejected inserting into provider_profiles / provider_details (Foreign Key 23503 / RLS).\n\n'
                'Please copy and run this quick SQL in your Supabase SQL Editor:',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  sqlCode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.lightGreenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Error details: $error',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: sqlCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 SQL script copied to clipboard! Paste it into Supabase SQL Editor.'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy SQL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOnlineStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to access the Technician Dashboard.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_isApproved) {
      final shouldActivate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Technician Activation'),
          content: const Text(
            'Your account is not registered as a verified technician yet.\n\n'
            'Would you like to activate your technician profile now so you can go online and receive jobs?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
              ),
              child: const Text('⚡ Activate & Go Online'),
            ),
          ],
        ),
      );

      if (shouldActivate == true) {
        await _activateAsTechnician(andGoOnline: true);
      }
      return;
    }

    setState(() => _isUpdating = true);
    final nextStatus = !_isOnline;

    try {
      await Supabase.instance.client.from('provider_details').upsert(
        {
          'user_id': user.id,
          'is_online': nextStatus,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      if (nextStatus) {
        try {
          await NotificationService.instance.syncTokenWithSupabase();
          final pos = await Geolocator.getCurrentPosition();
          await Supabase.instance.client.from('provider_locations').upsert(
            {
              'provider_id': user.id,
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'recorded_at': DateTime.now().toIso8601String(),
            },
            onConflict: 'provider_id',
          );
        } catch (locErr) {
          debugPrint('Location broadcast warning: $locErr');
        }
      }

      if (mounted) {
        setState(() {
          _isOnline = nextStatus;
          _isUpdating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      if (e is PostgrestException && e.code == '23503') {
        _showActivationHelpDialog(e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _createDemoJob() async {
    setState(() => _isUpdating = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw 'Please sign in first.';
      }

      double lat = 28.6139;
      double lng = 77.2090;
      try {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

      final services = [
        'Flat Tyre Assistance',
        'Battery Jumpstart',
        'Emergency Fuel (5L Petrol)',
        'Emergency Towing',
        'Engine Overheating Inspection',
      ];
      final serviceType = services[DateTime.now().second % services.length];

      await Supabase.instance.client.from('service_requests').insert({
        'customer_id': user.id,
        'service_type': serviceType,
        'description': 'Driver stranded on highway. Needs urgent $serviceType.',
        'latitude': lat + ((DateTime.now().millisecond % 10) - 5) * 0.001,
        'longitude': lng + ((DateTime.now().second % 10) - 5) * 0.001,
        'status': 'searching',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚗 Test emergency job "$serviceType" created!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating test job: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _buildEmptyJobsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.radar_outlined, size: 48, color: Colors.orange.shade300),
          const SizedBox(height: 12),
          const Text(
            'No Open Requests in Area',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Live radar is scanning for drivers needing assistance.\nTap below to simulate an incoming emergency job for testing:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isUpdating ? null : _createDemoJob,
            icon: const Icon(Icons.add_alert, size: 18),
            label: const Text('🚗 Simulate Driver Emergency Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobsList(List<Map<String, dynamic>> jobs) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        final job = jobs[index];
        final id = job['id'].toString();
        final service = job['service_type'] ?? 'Roadside Assistance';
        final desc = job['description'] ?? '';
        final time = job['created_at']?.toString().split('T').last.split('.').first ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.orange.shade100,
                  child: const Icon(Icons.build, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (desc.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Reported: $time • Status: Searching',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IncomingRequestScreen(requestId: id),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('View Job'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Technician Dashboard'),
        centerTitle: true,
        actions: [
          if (_isApproved)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Chip(
                avatar: const Icon(Icons.verified, color: Colors.green, size: 16),
                label: const Text('Verified', style: TextStyle(fontSize: 12, color: Colors.green)),
                backgroundColor: Colors.green.shade50,
                side: BorderSide(color: Colors.green.shade200),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Active Assigned Dispatch Banner
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client.auth.currentUser != null
                  ? Supabase.instance.client
                      .from('service_requests')
                      .stream(primaryKey: ['id'])
                      .eq('provider_id', Supabase.instance.client.auth.currentUser!.id)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final activeJobs = (snapshot.data ?? []).where((r) =>
                    ['accepted', 'in_progress'].contains(r['status'])).toList();

                if (activeJobs.isEmpty) return const SizedBox.shrink();

                final activeJob = activeJobs.first;
                final jobId = activeJob['id'].toString();
                final service = activeJob['service_type'] ?? 'Roadside Assistance';

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade400, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.navigation, color: Colors.green.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Active Dispatch in Progress!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade700,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                activeJob['status'].toString().toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You are assigned to $service. Continue live GPS turn-by-turn navigation to the driver.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TechnicianNavigationScreen(
                                    requestId: jobId,
                                    initialData: activeJob,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.directions),
                            label: const Text('🧭 Resume Live Navigation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (!_isApproved && !_isLoadingApproval) ...[
              Card(
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.engineering, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Technician Verification Required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your account is currently in Customer mode. Activate your certified technician profile to accept emergency jobs and broadcast GPS.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isUpdating ? null : () => _activateAsTechnician(andGoOnline: true),
                          icon: const Icon(Icons.flash_on),
                          label: const Text('⚡ 1-Tap Activate Technician Mode'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: _isOnline ? Colors.green : Colors.grey.shade400,
                      child: Icon(
                        _isOnline ? Icons.check_circle : Icons.offline_bolt,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isOnline ? 'You are ONLINE' : 'You are OFFLINE',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _isOnline ? Colors.green.shade800 : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOnline
                          ? 'Broadcasting GPS. Active requests will appear below.'
                          : 'Go online to accept roadside emergency jobs.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isUpdating ? null : _toggleOnlineStatus,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _isOnline ? Colors.red.shade700 : Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isUpdating
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _isOnline ? 'Go Offline' : 'Go Online & Broadcast GPS',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.flash_on, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Nearby Open Jobs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Feed',
                  onPressed: () => setState(() {}),
                ),
                TextButton.icon(
                  onPressed: _isUpdating ? null : _createDemoJob,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Test Job', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_isOnline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are currently OFFLINE. Toggle online above to accept jobs.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('service_requests')
                  .stream(primaryKey: ['id'])
                  .eq('status', 'searching')
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: Supabase.instance.client
                        .from('service_requests')
                        .select()
                        .eq('status', 'searching')
                        .order('created_at', ascending: false),
                    builder: (context, restSnapshot) {
                      if (restSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final restJobs = restSnapshot.data ?? [];
                      if (restJobs.isEmpty) {
                        return _buildEmptyJobsState();
                      }
                      return _buildJobsList(restJobs);
                    },
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final jobs = snapshot.data ?? [];
                if (jobs.isEmpty) {
                  return _buildEmptyJobsState();
                }
                return _buildJobsList(jobs);
              },
            ),
          ],
        ),
      ),
    );
  }
}
