import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final MapController _mapController = MapController();
  final Map<String, LatLng> _providerLocations = {};
  StreamSubscription? _providerSub;
  StreamSubscription? _requestSub;
  Timer? _pollingTimer;

  LatLng _userPosition = const LatLng(28.6139, 77.2090);
  Map<String, dynamic>? _activeRequest;
  Map<String, dynamic>? _techProfile;
  Map<String, dynamic>? _techDetails;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _locateUser();
    _initRealtimeTracking();
    _fetchActiveRequest();
    // 3-second poll for guaranteed real-time reflection between technician & user
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchActiveRequest();
      _fetchProviderLocationsFallback();
    });
  }

  Future<void> _locateUser() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _userPosition = userLatLng);
        _fitMap();
      }
    } catch (e) {
      debugPrint('Could not fetch location: $e');
    }
  }

  Future<void> _fetchActiveRequest() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('service_requests')
          .select()
          .eq('customer_id', user.id)
          .inFilter('status', ['searching', 'assigned', 'accepted', 'in_progress'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _activeRequest = data;
          _isLoading = false;
        });

        if (data != null && data['provider_id'] != null) {
          _fetchTechInfo(data['provider_id'].toString());
        } else {
          _techProfile = null;
          _techDetails = null;
        }

        _fitMap();
      }
    } catch (e) {
      debugPrint('Error fetching active request: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTechInfo(String providerId) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', providerId)
          .maybeSingle();

      final details = await Supabase.instance.client
          .from('provider_details')
          .select('vehicle_type, specialties')
          .eq('user_id', providerId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _techProfile = profile;
          _techDetails = details;
        });
        _fitMap();
      }
    } catch (e) {
      debugPrint('Error fetching tech info: $e');
    }
  }

  Future<void> _fetchProviderLocationsFallback() async {
    try {
      final data = await Supabase.instance.client
          .from('provider_locations')
          .select('provider_id, latitude, longitude');
      if (mounted) {
        setState(() {
          for (var row in data) {
            final id = row['provider_id'].toString();
            final lat = (row['latitude'] as num?)?.toDouble() ?? 28.6139;
            final lng = (row['longitude'] as num?)?.toDouble() ?? 77.2090;
            _providerLocations[id] = LatLng(lat, lng);
          }
        });
      }
    } catch (e) {
      debugPrint('Provider locations fallback error: $e');
    }
  }

  void _initRealtimeTracking() {
    _fetchProviderLocationsFallback();

    try {
      _providerSub = Supabase.instance.client
          .from('provider_locations')
          .stream(primaryKey: ['provider_id'])
          .handleError((error) => debugPrint('Provider stream error: $error'))
          .listen((data) {
            if (mounted) {
              setState(() {
                for (var row in data) {
                  final id = row['provider_id'].toString();
                  final lat = (row['latitude'] as num?)?.toDouble() ?? 28.6139;
                  final lng = (row['longitude'] as num?)?.toDouble() ?? 77.2090;
                  _providerLocations[id] = LatLng(lat, lng);
                }
              });
            }
          });

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _requestSub = Supabase.instance.client
            .from('service_requests')
            .stream(primaryKey: ['id'])
            .eq('customer_id', user.id)
            .handleError((error) => debugPrint('Request stream error: $error'))
            .listen((data) {
              final active = data.where((r) =>
                  ['searching', 'assigned', 'accepted', 'in_progress']
                      .contains(r['status'])).toList();
              if (active.isNotEmpty && mounted) {
                setState(() => _activeRequest = active.first);
                if (active.first['provider_id'] != null) {
                  _fetchTechInfo(active.first['provider_id'].toString());
                }
              }
            });
      }
    } catch (e) {
      debugPrint('Realtime init error: $e');
    }
  }

  void _fitMap() {
    final assignedTechId = _activeRequest?['provider_id']?.toString();
    final techPos = assignedTechId != null ? _providerLocations[assignedTechId] : null;

    if (techPos != null) {
      final bounds = LatLngBounds(_userPosition, techPos);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(70.0),
        ),
      );
    } else {
      _mapController.move(_userPosition, 14.0);
    }
  }

  double? _calculateDistanceToTech() {
    final assignedTechId = _activeRequest?['provider_id']?.toString();
    final techPos = assignedTechId != null ? _providerLocations[assignedTechId] : null;
    if (techPos == null) return null;
    const dist = Distance();
    final meters = dist.as(LengthUnit.Meter, _userPosition, techPos);
    return (meters / 1000.0);
  }

  Future<void> _cancelRequest() async {
    if (_activeRequest == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Assistance Request?'),
        content: const Text('Are you sure you want to cancel your roadside assistance request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Request')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('service_requests')
            .update({'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String()})
            .eq('id', _activeRequest!['id']);

        if (mounted) {
          setState(() {
            _activeRequest = null;
            _techProfile = null;
            _techDetails = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request has been cancelled.'), backgroundColor: Colors.orange),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cancelling: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available.')),
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
            title: const Text('Technician Contact'),
            content: SelectableText('Phone: $phone'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _providerSub?.cancel();
    _requestSub?.cancel();
    _pollingTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _activeRequest?['status'];
    final isAccepted = status == 'accepted' || status == 'in_progress';
    final isSearching = status == 'searching' || status == 'assigned';

    final assignedTechId = _activeRequest?['provider_id']?.toString();
    final techPos = assignedTechId != null ? _providerLocations[assignedTechId] : null;

    final distKm = _calculateDistanceToTech();
    final distText = distKm != null ? '${distKm.toStringAsFixed(1)} km away' : 'Nearby';
    final etaText = distKm != null ? '~${(distKm * 2.5).ceil()} mins' : '~5-10 mins';

    return Scaffold(
      appBar: AppBar(
        title: Text(isAccepted ? 'Technician En Route' : isSearching ? 'Searching Technician' : 'Live Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'My Location',
            onPressed: _locateUser,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: _fetchActiveRequest,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userPosition,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.jaldi_app',
              ),
              if (techPos != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_userPosition, techPos],
                      strokeWidth: 4.0,
                      color: Colors.green.shade700,
                      isDotted: true,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // User Marker
                  Marker(
                    point: _userPosition,
                    width: 50,
                    height: 50,
                    child: const Column(
                      children: [
                        Icon(Icons.person_pin_circle, color: Colors.blue, size: 36),
                        Text('You', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
                      ],
                    ),
                  ),
                  // Other Providers Markers
                  ..._providerLocations.entries.map((entry) {
                    final isAssignedThis = entry.key == assignedTechId;
                    return Marker(
                      point: entry.value,
                      width: 55,
                      height: 55,
                      child: Column(
                        children: [
                          Icon(
                            Icons.local_shipping,
                            color: isAssignedThis ? Colors.green.shade700 : Colors.orange,
                            size: isAssignedThis ? 36 : 28,
                          ),
                          Text(
                            isAssignedThis ? 'Your Tech' : 'Van',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isAssignedThis ? Colors.green.shade900 : Colors.black87,
                              backgroundColor: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // Top Status Pill
          if (isSearching)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Searching for nearest certified mechanic...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isAccepted)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status == 'in_progress'
                            ? 'Technician has arrived & is assisting you'
                            : 'Technician Assigned • $distText ($etaText)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Card
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
              child: _isLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  : isAccepted
                      ? _buildAcceptedTechCard(distText, etaText, status ?? 'accepted')
                      : isSearching
                          ? _buildSearchingCard()
                          : _buildNoActiveRequestCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedTechCard(String distText, String etaText, String status) {
    final techName = _techProfile?['full_name']?.toString().isNotEmpty == true
        ? _techProfile!['full_name'].toString()
        : 'Certified Highway Technician';
    final techPhone = _techProfile?['phone']?.toString();
    final vehicle = _techDetails?['vehicle_type']?.toString() ?? 'Mobile Service Van';
    final service = _activeRequest?['service_type'] ?? 'Roadside Assistance';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.green.shade100,
              child: const Icon(Icons.engineering, color: Colors.green, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    techName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$vehicle • $service',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          status == 'in_progress' ? 'ON SPOT' : 'EN ROUTE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$distText • ETA: $etaText',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: () => _callPhone(techPhone),
              style: IconButton.styleFrom(backgroundColor: Colors.green.shade700),
              icon: const Icon(Icons.phone, color: Colors.white),
              tooltip: 'Call Technician',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel Request'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchingCard() {
    final service = _activeRequest?['service_type'] ?? 'Roadside Assistance';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Colors.orange,
              child: Icon(Icons.car_repair, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Searching mechanics in 10 km radius...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const LinearProgressIndicator(color: Colors.orange),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _cancelRequest,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel Request'),
          ),
        ),
      ],
    );
  }

  Widget _buildNoActiveRequestCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No active emergency requests. Technicians are standing by nearby.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Return to Home'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
