import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'technician_navigation_screen.dart';

class IncomingRequestScreen extends ConsumerStatefulWidget {
  final String requestId;
  const IncomingRequestScreen({super.key, required this.requestId});

  @override
  ConsumerState<IncomingRequestScreen> createState() =>
      _IncomingRequestScreenState();
}

class _IncomingRequestScreenState extends ConsumerState<IncomingRequestScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _requestData;

  @override
  void initState() {
    super.initState();
    _fetchRequestDetails();
  }

  Future<void> _fetchRequestDetails() async {
    try {
      final data = await Supabase.instance.client
          .from('service_requests')
          .select('*, profiles(full_name, phone)')
          .eq('id', widget.requestId)
          .single();
      setState(() => _requestData = data);
    } catch (e) {
      debugPrint('Error fetching request: $e');
    }
  }

  Future<void> _handleResponse(bool accept) async {
    setState(() => _isLoading = true);
    try {
      if (accept) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw 'Please sign in first.';

        // PROFESSIONAL ATOMIC UPDATE:
        // We use a filtered update to ensure we only accept if the status is still 'searching'.
        // This prevents the race condition where two technicians accept the same job.
        final response = await Supabase.instance.client
            .from('service_requests')
            .update({
              'provider_id': user.id,
              'status': 'accepted',
              'accepted_at': DateTime.now().toIso8601String(),
            })
            .eq('id', widget.requestId)
            .eq('status', 'searching'); // CRITICAL: Only accept if still searching

        if (response.isEmpty) {
          throw 'This request has already been accepted by another technician.';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request accepted! Navigating to customer...'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TechnicianNavigationScreen(
                requestId: widget.requestId,
                initialData: _requestData,
              ),
            ),
          );
        }
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_requestData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final customer = _requestData!['profiles'] as Map<String, dynamic>?;
    final customerName = (customer != null &&
            customer['full_name'] != null &&
            customer['full_name'].toString().trim().isNotEmpty)
        ? customer['full_name'].toString()
        : 'Highway Driver in Need';
    final customerPhone = (customer != null &&
            customer['phone'] != null &&
            customer['phone'].toString().trim().isNotEmpty)
        ? customer['phone'].toString()
        : 'Available after acceptance';

    return Scaffold(
      backgroundColor: Colors.orange.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 80,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              const Text(
                'New Help Request!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        Icons.person,
                        'Customer',
                        customerName,
                      ),
                      const Divider(),
                      _buildDetailRow(Icons.phone, 'Phone', customerPhone),
                      const Divider(),
                      _buildDetailRow(
                        Icons.build,
                        'Issue',
                        _requestData!['service_type'],
                      ),
                      const Divider(),
                      _buildDetailRow(
                        Icons.location_on,
                        'Location',
                        'Nearby (check map)',
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleResponse(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleResponse(true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
