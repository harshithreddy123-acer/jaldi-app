import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TechnicianNavigationScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic>? initialData;

  const TechnicianNavigationScreen({
    super.key,
    required this.requestId,
    this.initialData,
  });

  @override
  State<TechnicianNavigationScreen> createState() =>
      _TechnicianNavigationScreenState();
}

class _TechnicianNavigationScreenState
    extends State<TechnicianNavigationScreen> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? _request;
  LatLng? _techPosition;
  LatLng? _customerPosition;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription? _requestSub;
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    _request = widget.initialData;
    _parsePositions();
    _loadRequestData();
    _startGpsBroadcasting();
    _listenToRequest();
  }

  void _parsePositions() {
    if (_request != null) {
      final cLat = (_request!['latitude'] as num?)?.toDouble();
      final cLng = (_request!['longitude'] as num?)?.toDouble();
      if (cLat != null && cLng != null) {
        _customerPosition = LatLng(cLat, cLng);
      }
    }
  }

  Future<void> _loadRequestData() async {
    try {
      final data = await Supabase.instance.client
          .from('service_requests')
          .select('*, profiles:customer_id(full_name, phone)')
          .eq('id', widget.requestId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _request = data;
          _parsePositions();
        });
        _fitMapBounds();
      }
    } catch (e) {
      debugPrint('Error loading request data: $e');
    }
  }

  void _listenToRequest() {
    _requestSub = Supabase.instance.client
        .from('service_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.requestId)
        .listen((data) {
          if (data.isNotEmpty && mounted) {
            setState(() {
              _request = {...?_request, ...data.first};
              _parsePositions();
            });
          }
        });
  }

  Future<void> _startGpsBroadcasting() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final user = Supabase.instance.client.auth.currentUser;
      if (mounted) {
        setState(() {
          _techPosition = LatLng(pos.latitude, pos.longitude);
        });
        _fitMapBounds();
      }

      if (user != null) {
        await Supabase.instance.client.from('provider_locations').upsert({
          'provider_id': user.id,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) async {
        if (!mounted) return;
        setState(() {
          _techPosition = LatLng(p.latitude, p.longitude);
        });

        final currentUid = Supabase.instance.client.auth.currentUser?.id;
        if (currentUid != null) {
          try {
            await Supabase.instance.client.from('provider_locations').upsert({
              'provider_id': currentUid,
              'latitude': p.latitude,
              'longitude': p.longitude,
              'recorded_at': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            debugPrint('Location broadcast error: $e');
          }
        }
      });
    } catch (e) {
      debugPrint('GPS tracking error: $e');
    }
  }

  void _fitMapBounds() {
    if (_techPosition != null && _customerPosition != null) {
      final bounds = LatLngBounds(_techPosition!, _customerPosition!);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60.0),
        ),
      );
    } else if (_customerPosition != null) {
      _mapController.move(_customerPosition!, 15.0);
    }
  }

  double? _calculateDistanceKm() {
    if (_techPosition == null || _customerPosition == null) return null;
    const distance = Distance();
    final meters = distance.as(
      LengthUnit.Meter,
      _techPosition!,
      _customerPosition!,
    );
    return (meters / 1000.0);
  }

  Future<void> _updateJobStatus(String newStatus) async {
    setState(() => _isUpdatingStatus = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final updateData = <String, dynamic>{
        'status': newStatus,
        if (newStatus == 'completed')
          'completed_at': DateTime.now().toIso8601String(),
      };

      if (user != null) {
        updateData['provider_id'] = user.id;
      }

      await Supabase.instance.client
          .from('service_requests')
          .update(updateData)
          .eq('id', widget.requestId);

      setState(() {
        if (_request != null) {
          _request!['status'] = newStatus;
        }
      });

      if (mounted) {
        if (newStatus == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Job completed successfully! Great work.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to: $newStatus'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating job status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _openGoogleMapsNavigation() async {
    if (_customerPosition == null) return;
    final lat = _customerPosition!.latitude;
    final lng = _customerPosition!.longitude;
    final url =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  Future<void> _callCustomer(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not provided by driver.')),
      );
      return;
    }
    final url = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Customer Phone Number'),
            content: SelectableText('Driver Phone: $phone'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _requestSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _request?['status'] ?? 'accepted';
    final serviceType = _request?['service_type'] ?? 'Roadside Assistance';
    final desc = _request?['description'] ?? '';

    final customerProfile = _request?['profiles'] as Map<String, dynamic>?;
    final customerName = customerProfile?['full_name']?.toString().isNotEmpty == true
        ? customerProfile!['full_name'].toString()
        : 'Stranded Driver';
    final customerPhone = customerProfile?['phone']?.toString();

    final distKm = _calculateDistanceKm();
    final distText = distKm != null ? '${distKm.toStringAsFixed(1)} km away' : 'Calculating...';
    final etaText = distKm != null ? '~${(distKm * 2.5).ceil()} mins drive' : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Job Navigation'),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Center on Me',
            onPressed: () {
              if (_techPosition != null) {
                _mapController.move(_techPosition!, 15.0);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit Route',
            onPressed: _fitMapBounds,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _customerPosition ?? const LatLng(28.6139, 77.2090),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.jaldi_app',
              ),
              if (_techPosition != null && _customerPosition != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_techPosition!, _customerPosition!],
                      strokeWidth: 4.0,
                      color: Colors.blue.shade700,
                      isDotted: true,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_customerPosition != null)
                    Marker(
                      point: _customerPosition!,
                      width: 50,
                      height: 50,
                      child: const Column(
                        children: [
                          Icon(Icons.location_on, color: Colors.red, size: 36),
                          Text('Driver', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
                        ],
                      ),
                    ),
                  if (_techPosition != null)
                    Marker(
                      point: _techPosition!,
                      width: 50,
                      height: 50,
                      child: const Column(
                        children: [
                          Icon(Icons.local_shipping, color: Colors.orange, size: 36),
                          Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Top Status Pill
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Icon(Icons.navigation, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status == 'in_progress' ? 'On Spot • Servicing Vehicle' : 'En Route • $distText $etaText',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: status == 'in_progress' ? Colors.blue : Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Navigation Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.orange.shade100,
                        child: const Icon(Icons.build, color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              serviceType,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              customerName,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _callCustomer(customerPhone),
                        icon: const Icon(Icons.phone, color: Colors.green),
                        tooltip: 'Call Driver',
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _openGoogleMapsNavigation,
                        style: IconButton.styleFrom(backgroundColor: Colors.blue.shade700),
                        icon: const Icon(Icons.directions, color: Colors.white),
                        tooltip: 'Open in Google Maps',
                      ),
                    ],
                  ),
                  if (desc.toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Note: $desc',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_isUpdatingStatus)
                    const Center(child: CircularProgressIndicator())
                  else if (status == 'accepted') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateJobStatus('in_progress'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('📍 I Have Arrived at Driver Spot'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ] else if (status == 'in_progress') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateJobStatus('completed'),
                        icon: const Icon(Icons.task_alt),
                        label: const Text('✅ Service Completed'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
