import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleNumberController = TextEditingController();

  String _bloodGroup = 'O+';
  String _userRole = 'customer';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;

  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _vehicleModelController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final user = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    // 1. Load from local cache first for instant UI response
    _nameController.text = prefs.getString('user_name') ?? user?.userMetadata?['full_name'] ?? '';
    _phoneController.text = prefs.getString('user_phone') ?? user?.userMetadata?['phone'] ?? '';
    _ageController.text = prefs.getString('user_age') ?? '';
    _cityController.text = prefs.getString('user_city') ?? '';
    _addressController.text = prefs.getString('user_address') ?? '';
    _emergencyNameController.text = prefs.getString('user_emergency_name') ?? '';
    _emergencyPhoneController.text = prefs.getString('user_emergency_phone') ?? '';
    _vehicleModelController.text = prefs.getString('user_vehicle_model') ?? '';
    _vehicleNumberController.text = prefs.getString('user_vehicle_number') ?? '';
    _bloodGroup = prefs.getString('user_blood_group') ?? 'O+';

    // 2. Fetch from Supabase profiles table
    if (user != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null && mounted) {
          setState(() {
            _userRole = profile['role']?.toString() ?? 'customer';
            if ((profile['full_name']?.toString().isNotEmpty ?? false)) {
              _nameController.text = profile['full_name'].toString();
            }
            if ((profile['phone']?.toString().isNotEmpty ?? false)) {
              _phoneController.text = profile['phone'].toString();
            }
            if (profile['age'] != null) {
              _ageController.text = profile['age'].toString();
            }
            if (profile['city'] != null) {
              _cityController.text = profile['city'].toString();
            }
            if (profile['address'] != null) {
              _addressController.text = profile['address'].toString();
            }
            if (profile['emergency_contact_name'] != null) {
              _emergencyNameController.text =
                  profile['emergency_contact_name'].toString();
            }
            if (profile['emergency_contact_phone'] != null) {
              _emergencyPhoneController.text =
                  profile['emergency_contact_phone'].toString();
            }
            if (profile['blood_group'] != null &&
                _bloodGroups.contains(profile['blood_group'])) {
              _bloodGroup = profile['blood_group'].toString();
            }
            if (profile['vehicle_model'] != null) {
              _vehicleModelController.text =
                  profile['vehicle_model'].toString();
            }
            if (profile['vehicle_number'] != null) {
              _vehicleNumberController.text =
                  profile['vehicle_number'].toString();
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching cloud profile: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final locText = 'GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';

      if (mounted) {
        setState(() {
          if (_cityController.text.isEmpty) {
            _cityController.text = 'Near Highway / Expressway';
          }
          if (_addressController.text.isEmpty) {
            _addressController.text = locText;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Location updated: $locText'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch GPS location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final user = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    // 1. Cache to local storage immediately
    await prefs.setString('user_name', _nameController.text.trim());
    await prefs.setString('user_phone', _phoneController.text.trim());
    await prefs.setString('user_age', _ageController.text.trim());
    await prefs.setString('user_city', _cityController.text.trim());
    await prefs.setString('user_address', _addressController.text.trim());
    await prefs.setString('user_emergency_name', _emergencyNameController.text.trim());
    await prefs.setString('user_emergency_phone', _emergencyPhoneController.text.trim());
    await prefs.setString('user_vehicle_model', _vehicleModelController.text.trim());
    await prefs.setString('user_vehicle_number', _vehicleNumberController.text.trim());
    await prefs.setString('user_blood_group', _bloodGroup);

    // 2. Save to Supabase
    if (user != null) {
      final baseUpdates = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Try writing all extended columns
      try {
        await Supabase.instance.client.from('profiles').update({
          ...baseUpdates,
          'age': int.tryParse(_ageController.text.trim()),
          'city': _cityController.text.trim(),
          'address': _addressController.text.trim(),
          'emergency_contact_name': _emergencyNameController.text.trim(),
          'emergency_contact_phone': _emergencyPhoneController.text.trim(),
          'blood_group': _bloodGroup,
          'vehicle_model': _vehicleModelController.text.trim(),
          'vehicle_number': _vehicleNumberController.text.trim(),
        }).eq('id', user.id);
      } catch (dbErr) {
        debugPrint('Extended update warning, falling back to base columns: $dbErr');
        try {
          await Supabase.instance.client.from('profiles').update(baseUpdates).eq('id', user.id);
        } catch (baseErr) {
          debugPrint('Base update error: $baseErr');
        }
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profile details saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _callEmergencyContact() async {
    final phone = _emergencyPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an emergency contact phone number first.')),
      );
      return;
    }
    final url = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calling $phone')),
        );
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to log out of your Jaldi account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'driver@jaldi.app';
    final isTech = _userRole == 'provider';

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Avatar & Badge Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: isTech ? Colors.green.shade100 : Colors.orange.shade100,
                        child: Icon(
                          isTech ? Icons.engineering : Icons.person,
                          size: 48,
                          color: isTech ? Colors.green.shade800 : Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _nameController.text.trim().isNotEmpty
                            ? _nameController.text.trim()
                            : 'Driver Profile',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      Chip(
                        avatar: Icon(
                          isTech ? Icons.verified : Icons.directions_car,
                          size: 16,
                          color: isTech ? Colors.green : Colors.blue,
                        ),
                        label: Text(
                          isTech ? 'Certified Highway Technician' : 'Jaldi Verified Driver',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isTech ? Colors.green.shade800 : Colors.blue.shade900,
                          ),
                        ),
                        backgroundColor: isTech ? Colors.green.shade50 : Colors.blue.shade50,
                        side: BorderSide(
                          color: isTech ? Colors.green.shade200 : Colors.blue.shade200,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Section 1: Personal Details
              _buildSectionHeader(Icons.badge, 'Personal Information'),
              const SizedBox(height: 10),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your full name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: '+91 98765 43210',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter mobile number' : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Age',
                                prefixIcon: Icon(Icons.cake_outlined),
                                hintText: 'e.g. 28',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _bloodGroup,
                              decoration: const InputDecoration(
                                labelText: 'Blood Group',
                                prefixIcon: Icon(Icons.bloodtype_outlined),
                                border: OutlineInputBorder(),
                              ),
                              items: _bloodGroups.map((bg) {
                                return DropdownMenuItem(value: bg, child: Text(bg));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _bloodGroup = val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Section 2: Location & Address
              _buildSectionHeader(Icons.location_on, 'Location & Address'),
              const SizedBox(height: 10),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: 'City / Region',
                                prefixIcon: Icon(Icons.location_city),
                                hintText: 'e.g. New Delhi, Mumbai',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _isLocating ? null : _detectLocation,
                            icon: _isLocating
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.my_location, size: 16),
                            label: const Text('GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Residential / Office Address',
                          prefixIcon: Icon(Icons.home_outlined),
                          hintText: 'Street, area, landmark, and pin code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Section 3: Emergency Contacts (Critical for Roadside & Accidents)
              _buildSectionHeader(Icons.emergency, 'Emergency Contact (SOS)'),
              const SizedBox(height: 10),
              Card(
                color: Colors.red.shade50.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This contact is notified in critical accidents or SOS panic activations.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emergencyNameController,
                        decoration: const InputDecoration(
                          labelText: 'Contact Person Name & Relation',
                          prefixIcon: Icon(Icons.person_pin),
                          hintText: 'e.g. Rahul Sharma (Brother)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emergencyPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Emergency Mobile Number',
                                prefixIcon: Icon(Icons.phone_in_talk),
                                hintText: '+91 98765 00000',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: _callEmergencyContact,
                            style: IconButton.styleFrom(backgroundColor: Colors.red.shade700),
                            icon: const Icon(Icons.call, color: Colors.white),
                            tooltip: 'Test Call',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Section 4: Vehicle Details
              _buildSectionHeader(Icons.directions_car, 'Registered Vehicle Details'),
              const SizedBox(height: 10),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _vehicleModelController,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle Brand & Model',
                          prefixIcon: Icon(Icons.car_repair),
                          hintText: 'e.g. Hyundai Creta / Honda City / RE Classic 350',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _vehicleNumberController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle Registration Plate Number',
                          prefixIcon: Icon(Icons.pin),
                          hintText: 'e.g. DL 03 AB 1234',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Section 5: App Preferences
              _buildSectionHeader(Icons.palette, 'Preferences & Theme'),
              const SizedBox(height: 10),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.color_lens_outlined),
                    title: const Text('App Color Theme'),
                    trailing: DropdownButton<ThemeMode>(
                      value: themeMode,
                      underline: const SizedBox.shrink(),
                      onChanged: (mode) {
                        if (mode != null) {
                          ref.read(themeProvider.notifier).setTheme(mode);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: ThemeMode.system, child: Text('System Default')),
                        DropdownMenuItem(value: ThemeMode.light, child: Text('Light Mode')),
                        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark Mode')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Save Button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveProfile,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSaving ? 'Saving Changes...' : 'Save Profile Details',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sign out button
              OutlinedButton.icon(
                onPressed: _confirmSignOut,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
