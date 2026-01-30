import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const PocketParkingApp());
}

// --- CONSTANTS ---
const String backendUrl = "https://parking-production-cb72.up.railway.app";
const String noirMapStyle = '''
[
  { "elementType": "geometry", "stylers": [{ "color": "#212121" }] },
  { "elementType": "labels.icon", "stylers": [{ "visibility": "off" }] },
  { "elementType": "labels.text.fill", "stylers": [{ "color": "#757575" }] },
  { "elementType": "labels.text.stroke", "stylers": [{ "color": "#212121" }] },
  { "featureType": "administrative", "elementType": "geometry", "stylers": [{ "color": "#757575" }] },
  { "featureType": "poi", "elementType": "labels.text.fill", "stylers": [{ "color": "#757575" }] },
  { "featureType": "road", "elementType": "geometry.fill", "stylers": [{ "color": "#2c2c2c" }] },
  { "featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{ "color": "#3c3c3c" }] },
  { "featureType": "water", "elementType": "geometry", "stylers": [{ "color": "#000000" }] }
]
''';

// --- THEME ---
class PocketParkingApp extends StatelessWidget {
  const PocketParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Parking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: Colors.white,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFF888888)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Map State
  final Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  
  // UI State
  bool _isFinding = false;
  
  // Selected Spot Info
  Map<String, dynamic>? _selectedSpot;
  bool _showInfoCard = false;

  static const CameraPosition _kDefaultIndia = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 4,
  );

  @override
  void initState() {
    super.initState();
    // Request permission immediately so the Blue Dot appears on startup
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Refresh the UI to ensure the map picks up the new permission status
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Background Map
          // We use Positioned.fill to ensure it takes up space without complex wrappers
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _kDefaultIndia,
              mapType: MapType.normal,
              markers: _markers,
              zoomControlsEnabled: false,
              
              // --- BLUE DOT SETTINGS ---
              myLocationEnabled: true,       // Shows the Blue Dot
              myLocationButtonEnabled: false, // Hides the default target button (we have our own flow)
              // -------------------------

              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
                controller.setMapStyle(noirMapStyle);
              },
              onTap: (_) => setState(() => _showInfoCard = false),
            ),
          ),

          // 2. UI Overlay (Header & Buttons)
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  // Added a gradient so text is readable if map is light under it
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        "Pocket Parking.",
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "The city is full of empty spaces. Find yours.",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Action Area
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPrimaryButton(
                      text: _isFinding ? "Scanning..." : "Find Parking Near Me",
                      onPressed: _findParking,
                    ),
                    const SizedBox(width: 15),
                    _buildSecondaryButton(
                      text: "Rent my free space",
                      onPressed: () => _showRentModal(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Info Card (Floating Bottom)
          if (_showInfoCard && _selectedSpot != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: _buildInfoCard(),
            ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildPrimaryButton({required String text, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 10,
        shadowColor: Colors.white.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }

  Widget _buildSecondaryButton({required String text, required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF333333), width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF333333)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 30, spreadRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Available Spot", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              InkWell(
                onTap: () => setState(() => _showInfoCard = false),
                child: const Icon(Icons.close, color: Colors.grey),
              )
            ],
          ),
          const SizedBox(height: 5),
          Text(_selectedSpot?['address'] ?? "Loading...", style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                 final lat = _selectedSpot?['latitude'];
                 final lng = _selectedSpot?['longitude'];
                 if(lat != null && lng != null){
                   final uri = Uri.parse("http://maps.google.com/?q=$lat,$lng");
                   if(await canLaunchUrl(uri)) launchUrl(uri);
                 }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("↗ Get Directions", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // --- LOGIC: FIND PARKING ---

  Future<void> _findParking() async {
    setState(() => _isFinding = true);

    try {
      Position position = await _determinePosition();
      
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(position.latitude, position.longitude), zoom: 15),
      ));

      await _fetchAndShowSpots();
      
    } catch (e) {
      debugPrint("ERROR: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if(mounted) setState(() => _isFinding = false);
    }
  }

  Future<void> _fetchAndShowSpots() async {
    try {
      final response = await http.get(Uri.parse("$backendUrl/spots/"));
      if (response.statusCode == 200) {
        final dynamic jsonResponse = jsonDecode(response.body);
        final List<dynamic> spots = (jsonResponse is List) ? jsonResponse : (jsonResponse['data'] ?? []);

        Set<Marker> newMarkers = {};
        for (var spot in spots) {
          final lat = spot['latitude'];
          final lng = spot['longitude'];
          
          newMarkers.add(Marker(
            markerId: MarkerId("${lat}_$lng"),
            position: LatLng(lat, lng),
            // Default Azure-ish Hue for contrast
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            onTap: () {
              setState(() {
                _selectedSpot = spot;
                _showInfoCard = true;
              });
            },
          ));
        }

        setState(() {
          _markers = newMarkers;
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }


  // --- LOGIC: RENT MODAL ---

  void _showRentModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) => const RentDialog(),
    );
  }
}

// --- RENT DIALOG WIDGET ---

class RentDialog extends StatefulWidget {
  const RentDialog({super.key});

  @override
  State<RentDialog> createState() => _RentDialogState();
}

class _RentDialogState extends State<RentDialog> {
  final Completer<GoogleMapController> _rentMapController = Completer();
  LatLng _currentPinPosition = const LatLng(20.5937, 78.9629);
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _centerOnUser();
  }

  void _centerOnUser() async {
    try {
      Position p = await Geolocator.getCurrentPosition();
      final pos = LatLng(p.latitude, p.longitude);
      
      if(mounted) setState(() => _currentPinPosition = pos);
      
      final controller = await _rentMapController.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17)));
    } catch(e) {
      // Ignore if permission not granted yet, user can drag manually
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Modal Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            color: Colors.black,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("📍 Where is your spot?", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
          ),
          
          // Map Area
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _currentPinPosition, zoom: 4),
                  myLocationEnabled: true, // Show blue dot here too
                  myLocationButtonEnabled: false,
                  onMapCreated: (c) {
                    _rentMapController.complete(c);
                    c.setMapStyle(noirMapStyle);
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId("rent_pin"),
                      position: _currentPinPosition,
                      draggable: true,
                      onDragEnd: (pos) => setState(() => _currentPinPosition = pos),
                    )
                  },
                  onTap: (pos) => setState(() => _currentPinPosition = pos),
                ),
                
                // Controls
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: _centerOnUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF333333),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("🎯 Jump to my location"),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isPublishing ? null : _submitLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.all(18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                            elevation: 10,
                          ),
                          child: Text(_isPublishing ? "Publishing..." : "List This Location", 
                             style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _submitLocation() async {
    setState(() => _isPublishing = true);
    
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/mark-spot/"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "latitude": _currentPinPosition.latitude,
          "longitude": _currentPinPosition.longitude,
          "owner_name": "App User"
        }),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if(mounted) {
           Navigator.pop(context);
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("✅ Spot Listed! ${result['data']['address'] ?? ''}"), backgroundColor: Colors.green)
           );
        }
      } else {
        throw result['detail'] ?? "Unknown Error";
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if(mounted) setState(() => _isPublishing = false);
    }
  }
}