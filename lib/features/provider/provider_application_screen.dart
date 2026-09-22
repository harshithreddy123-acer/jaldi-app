import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProviderApplicationScreen extends ConsumerStatefulWidget {
  const ProviderApplicationScreen({super.key});

  @override
  @override
  ConsumerState<ProviderApplicationScreen> createState() =>
      _ProviderApplicationScreenState();
}

class _ProviderApplicationScreenState
    extends ConsumerState<ProviderApplicationScreen> {
  final _vehicleController = TextEditingController();
  final _specialtiesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _vehicleController.dispose();
    _specialtiesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_vehicleController.text.trim().isEmpty ||
        _specialtiesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Complete all fields.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw const AuthException('Please sign in again.');
      await Supabase.instance.client.from('provider_applications').insert({
        'user_id': user.id,
        'vehicle_type': _vehicleController.text.trim(),
        'specialties': _specialtiesController.text.trim(),
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application submitted for review.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit application: ${error.message}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become a Technician')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Application Form',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Submit your details. Our admin will review your application.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _vehicleController,
                decoration: InputDecoration(
                  labelText: 'Vehicle Type (e.g. Bike, Van)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _specialtiesController,
                decoration: InputDecoration(
                  labelText: 'Specialties (e.g. Tyre, Battery)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Submit Application'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
