// lib/services/location_service.dart

import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:location/location.dart';
import 'dart:async'; // For TimeoutException

// Enum to represent the outcome of the location request
enum LocationResultStatus {
  success,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever, // Added for permanent denial
  timeout,
  unknownError,
}

// Class to hold the result: either location data or an error status/message
class LocationResult {
  final LocationData? locationData;
  final LocationResultStatus status;
  final String? errorMessage; // Optional message for logging or specific errors

  LocationResult({
    this.locationData,
    required this.status,
    this.errorMessage,
  });
}

/// Service class to handle location fetching and permission checks.
class LocationService {
  final Location _location = Location();

  /// Gets the current device location after checking/requesting services and permissions.
  ///
  /// Returns a [LocationResult] object containing either the [LocationData] on success,
  /// or an error status and optional message on failure.
  Future<LocationResult> getCurrentLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // --- 1. Check Location Service ---
    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      debugPrint("Location service disabled. Requesting service...");
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        debugPrint("Location service request denied by user.");
        return LocationResult(
          status: LocationResultStatus.serviceDisabled,
          errorMessage: 'Location services are disabled. Please enable them.',
        );
      }
    }

    // --- 2. Check Location Permissions ---
    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      debugPrint("Location permission denied. Requesting permission...");
      permissionGranted = await _location.requestPermission();
      if (permissionGranted == PermissionStatus.denied) {
        debugPrint("Location permission request denied by user.");
        return LocationResult(
          status: LocationResultStatus.permissionDenied,
          errorMessage: 'Location permission is required to mark attendance.',
        );
      } else if (permissionGranted == PermissionStatus.deniedForever) {
         debugPrint("Location permission permanently denied by user.");
         return LocationResult(
           status: LocationResultStatus.permissionDeniedForever,
           errorMessage: 'Location permission is permanently denied. Please enable it in app settings.',
         );
      }
    }

    // Handle case where permission might still not be granted (e.g., deniedForever was already set)
     if (permissionGranted != PermissionStatus.granted && permissionGranted != PermissionStatus.grantedLimited) {
        debugPrint("Location permission not granted (Status: $permissionGranted).");
        // Determine if it was permanently denied
        if (permissionGranted == PermissionStatus.deniedForever) {
           return LocationResult(
             status: LocationResultStatus.permissionDeniedForever,
             errorMessage: 'Location permission is permanently denied. Please enable it in app settings.',
           );
        } else {
           return LocationResult(
             status: LocationResultStatus.permissionDenied,
             errorMessage: 'Location permission was not granted.',
           );
        }
     }


    // --- 3. Get Location Data ---
    debugPrint("Location services and permissions OK. Getting location...");
    try {
      // Set desired accuracy
      await _location.changeSettings(accuracy: LocationAccuracy.high);
      // Get location with timeout
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 15), // Keep timeout reasonable
        onTimeout: () {
          // This callback executes if timeout occurs
          debugPrint("Getting location timed out.");
          // Throw an exception that the catch block below will handle
          throw TimeoutException('Getting location timed out after 15 seconds.');
        },
      );
      debugPrint("Location fetched: Lat ${locationData.latitude}, Lon ${locationData.longitude}");
      return LocationResult(
        status: LocationResultStatus.success,
        locationData: locationData,
      );
    } on TimeoutException catch (e) {
       // Catch the specific timeout exception thrown above or by the timeout method itself
       return LocationResult(
         status: LocationResultStatus.timeout,
         errorMessage: e.message ?? 'Could not get location in time. Please try again.',
       );
    } catch (e) {
      // Catch any other platform exceptions during getLocation
      debugPrint("Error getting location: $e");
      return LocationResult(
        status: LocationResultStatus.unknownError,
        errorMessage: 'An unexpected error occurred while getting location: ${e.toString()}',
      );
    }
  }
}