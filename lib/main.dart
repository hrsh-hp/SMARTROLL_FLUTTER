import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'Screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // You might also want to make system bars transparent
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // Adjust for your app's theme
      systemNavigationBarIconBrightness: Brightness.dark, // Adjust
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _appLinks = AppLinks();
  final _storage = const FlutterSecureStorage();
  StreamSubscription<Uri>? _linkSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        //debugprint('Initial link received: $initialUri');
        await _processLink(initialUri);
      } else {
        //debugprint('No initial link found.');
      }
    } catch (e) {
      //debugprint('Error getting initial link: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        //debugprint('Link received while running: $uri');
        _processLink(uri);
      },
      onError: (err) {
        //debugprint('Error listening to link stream: $err');
      },
    );
  }

  Future<void> _processLink(Uri uri) async {
    if (uri.scheme == 'smartrollauth' && uri.host == 'callback') {
      final String? accessToken = uri.queryParameters['access_token'];
      final String? refreshToken = uri.queryParameters['refresh_token'];

      if (accessToken != null &&
          accessToken.isNotEmpty &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        try {
          await _storage.write(key: 'accessToken', value: accessToken);
          await _storage.write(key: 'refreshToken', value: refreshToken);
          //debugprint("Tokens stored successfully via deep link!");

          // Use the navigator key to push a fresh instance of SplashScreen
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const SplashScreen()),
            (route) => false,
          );
        } catch (e) {
          //debugprint("Failed to store tokens from link: $e");
        }
      } else {
        //debugprint("Auth callback received but tokens are missing/empty: $uri");
      }
    } else {
      //debugprint("Received link is not the expected auth callback: $uri");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'SmartRoll Attendance',
      // In your main.dart
      theme: ThemeData(
        brightness: Brightness.light, // *** CHANGED ***
        primaryColor: Colors.black, // Example: Changed primary
        colorScheme: ColorScheme.light(
          // *** CHANGED to light ***
          primary: Colors.black, // Example: Dark primary
          secondary: Colors.blueGrey, // Example: Muted secondary
          surface: const Color(0xFFFFFFFF), // Card/Dialog background (Correct)
          onPrimary: Colors.white, // Text on dark primary elements
          onSecondary: Colors.white, // Text on secondary elements
          onSurface: Colors.black87, // Text on cards (*** IMPORTANT ***)
          onSurfaceVariant: Colors.black87, // Text on (*** IMPORTANT ***)
          error: Colors.redAccent,
          onError: Colors.white,
          secondaryContainer: const Color(0xFFF7F7F7),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme,
        ).apply(
          // Optionally apply default colors
          bodyColor: Colors.black87,
          displayColor: Colors.black87,
        ),
        fontFamily: GoogleFonts.poppins().fontFamily,
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          centerTitle: true, // Keep if desired, target seems left-aligned logo
          elevation: 2,
          iconTheme: IconThemeData(color: Colors.black54), // *** CHANGED ***
          actionsIconTheme: IconThemeData(
            color: Colors.black54,
          ), // *** Ensure actions icons are also dark ***
          titleTextStyle: GoogleFonts.poppins(
            // Explicitly use Poppins here too if desired
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          // Looks good, keep as is
          color: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            side: const BorderSide(
              color: Color(0xFFFAFAFA),
              width: 1.5,
            ), // Adjusted width slightly
            borderRadius: BorderRadius.circular(
              12.0,
            ), // Slightly larger radius like target
          ),
          elevation: 2,
          shadowColor: Colors.grey.shade200, // Lighter shadow for light theme
          margin: const EdgeInsets.symmetric(
            vertical: 8.0,
            horizontal: 12.0,
          ), // Adjusted margin slightly
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          // Keep basic shape
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            // Consider adding default text/background colors if needed
            backgroundColor: Colors.blueAccent[400],
            // foregroundColor: Colors.white, // Example
            disabledBackgroundColor: Colors.grey.shade400,
            disabledForegroundColor: Colors.grey.shade700,
          ),
        ),
        iconTheme: IconThemeData(
          // Default icon color
          color: Colors.black54,
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
