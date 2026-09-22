import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/tracking_screen.dart';

class RequestScreen extends ConsumerStatefulWidget {
  const RequestScreen({super.key});

  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends ConsumerState<RequestScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _notesController = TextEditingController();

  LatLng _currentPosition = const LatLng(28.6139, 77.2090);
  String? _selectedService = 'Tyre Puncture';
  bool _isRequesting = false;
  bool _isLocating = false;

  final List<String> _services = [
    'Tyre Puncture',
    'Battery Jumpstart',
    'Emergency Fuel (5L)',
    'Engine Failure',
    'Towing Service',
    'Key Lockout / Other',
  ];

  @override
  void initState() {
    super.initState();
    _fetchFastLocation();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchFastLocation() async {
    setState(() => _isLocating = true);

    try {
      // 1. Instant cache check (0.01 sec)
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        final posLatLng = LatLng(lastPos.latitude, lastPos.longitude);
        setState(() => _currentPosition = posLatLng);
        _mapController.move(posLatLng, 15.0);
      }

      // 2. Permission check
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      // 3. Fast position with 4-second timeout to avoid long waits
      final currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );

      if (mounted) {
        final newLatLng = LatLng(currentPos.latitude, currentPos.longitude);
        setState(() {
          _currentPosition = newLatLng;
          _isLocating = false;
        });
        _mapController.move(newLatLng, 15.0);
      }
    } catch (e) {
      debugPrint('Fast location fetch completed or timed out: $e');
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an assistance service.')),
      );
      return;
    }

    setState(() => _isRequesting = true);
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => _isRequesting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to request assistance.')),
        );
      }
      return;
    }

    try {
      await Supabase.instance.client.from('service_requests').insert({
        'customer_id': user.id,
        'service_type': _selectedService,
        'description': _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : 'Driver breakdown at pinned GPS location.',
        'latitude': _currentPosition.latitude,
        'longitude': _currentPosition.longitude,
        'status': 'searching',
      });

      // Query nearest online technicians via PostGIS function
      int nearestCount = 0;
      try {
        final nearest = await Supabase.instance.client.rpc(
          'find_nearest_technicians',
          params: {
            'p_lat': _currentPosition.latitude,
            'p_lng': _currentPosition.longitude,
            'p_radius_meters': 25000.0,
          },
        ) as List<dynamic>?;
        nearestCount = nearest?.length ?? 0;
      } catch (rpcErr) {
        debugPrint('find_nearest_technicians notice: $rpcErr');
      }

      if (mounted) {
        final alertText = nearestCount > 0
            ? '🚀 Request submitted! Alerting $nearestCount nearby technician(s)...'
            : '🚀 Request submitted! Finding nearest available technicians...';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alertText),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TrackingScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Assistance'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                  )
                : const Icon(Icons.my_location),
            tooltip: 'Find My Location',
            onPressed: _fetchFastLocation,
          ),
        ],
      ),
      body: Column(
        children: [
          // Instant FlutterMap (OpenStreetMap)
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: 15.0,
                    onTap: (tapPosition, point) {
                      setState(() => _currentPosition = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.jaldi_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition,
                          width: 80,
                          height: 80,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.red,
                                child: Icon(Icons.car_crash, color: Colors.white, size: 24),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Breakdown Spot',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  backgroundColor: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Hint overlay
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, color: Colors.orangeAccent, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Tap map anywhere to adjust vehicle location',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Service details & confirmation
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3)),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Assistance Needed',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _services.map((service) {
                        final isSelected = _selectedService == service;
                        return ChoiceChip(
                          label: Text(service),
                          selected: isSelected,
                          selectedColor: Colors.orange.shade100,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.orange.shade900 : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedService = selected ? service : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Optional details for technician',
                        hintText: 'e.g. Right rear tyre flat, spare tyre available',
                        prefixIcon: const Icon(Icons.edit_note),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: (_selectedService == null || _isRequesting)
                            ? null
                            : _submitRequest,
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.flash_on),
                        label: Text(
                          _isRequesting ? 'Broadcasting...' : 'Confirm & Request Technician',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
