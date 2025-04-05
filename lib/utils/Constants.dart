import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The base URL for the backend API.
const String backendBaseUrl = "https://smartroll.mnv-dev.site"; 

/// A shared instance of FlutterSecureStorage for the entire application.
final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

// Note: Device ID cannot be a constant here as it's fetched asynchronously at runtime.
// Fetch it where needed (e.g., in the initState of relevant screens) and store it in local state.
