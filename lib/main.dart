import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart'; // Import the package
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Import secure storage
import 'Screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _appLinks = AppLinks(); // Create an instance of AppLinks
  final _storage = const FlutterSecureStorage();
  StreamSubscription<Uri>? _linkSubscription; // To manage the listener

  @override
  void initState() {
    super.initState();
    // Initialize link handling
    _initDeepLinks();
  }

  @override
  void dispose() {
    // Cancel the stream subscription when the widget is disposed
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    // --- Handle initial link when app starts ---
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('Initial link received: $initialUri');
        await _processLink(initialUri);
      } else {
        debugPrint('No initial link found.');
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }

    // --- Listen for incoming links while the app is running ---
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('Link received while running: $uri');
        // No need to await here, let it process in the background
        _processLink(uri);
      },
      onError: (err) {
        debugPrint('Error listening to link stream: $err');
        // Handle errors, maybe show a snackbar
      },
    );
  }

  /// Processes the received URI, extracts tokens, stores them.
  Future<void> _processLink(Uri uri) async {
    // Check if it's our specific callback scheme and host
    // Make sure 'smartrollauth' and 'callback' match your setup
    if (uri.scheme == 'smartrollauth' && uri.host == 'callback') {
      // Extract tokens from query parameters
      final String? accessToken = uri.queryParameters['access_token'];
      final String? refreshToken = uri.queryParameters['refresh_token'];

      // Validate tokens
      if (accessToken != null &&
          accessToken.isNotEmpty &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        try {
          // Store tokens securely
          await _storage.write(key: 'accessToken', value: accessToken);
          await _storage.write(key: 'refreshToken', value: refreshToken);
          debugPrint("Tokens stored successfully via deep link!");

          // **Navigation Note:** We don't need to navigate directly here.
          // Storing the tokens is enough. The SplashScreen will check
          // storage on the next run/check and navigate accordingly.
          // This simplifies the logic and avoids potential context issues.
        } catch (e) {
          debugPrint("Failed to store tokens from link: $e");
          // Optionally show an error message to the user (e.g., via a global snackbar service)
        }
      } else {
        debugPrint("Auth callback received but tokens are missing/empty: $uri");
        // Optionally show an error
      }
    } else {
      debugPrint("Received link is not the expected auth callback: $uri");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartRoll Attendance',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF000000),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          centerTitle: true,
          elevation: 2,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
        ),
        cardTheme: CardTheme(
          color: const Color(0x11111111),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF1F1F1F), width: 2),
            borderRadius: BorderRadius.circular(8.0),
          ),
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}


// ndk version
    // ndkVersion = flutter.ndkVersion
    // ndkVersion = "27.0.12077973", flutter  
