import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:peerchat_secure/firebase_options.dart';
import 'package:provider/provider.dart';
import 'src/app_state.dart';
import 'src/screens/first_sign_in_screen.dart';
import 'src/screens/main_shell.dart';
import 'src/services/first_sign_in_service.dart';
import 'src/services/menu_settings_service.dart';
import 'src/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  GoogleFonts.config.allowRuntimeFetching = false;

  // Immersive dark status/nav bars
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDeep,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  final FirstSignInService _firstSignInService = FirstSignInService();
  MenuSettingsController _menuSettingsController =
      MenuSettingsController();
  AppState? _appState;
  Object? _fatalError;
  bool _isLoading = true;
  bool _showFirstSignIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _appState?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _menuSettingsController.init();
      final decision = await _firstSignInService.evaluateFirstSignIn();
      if (decision.shouldShowChoice) {
        if (!mounted) return;
        setState(() {
          _showFirstSignIn = true;
          _isLoading = false;
        });
        return;
      }

      await _initializeAppState();
    } catch (e, stack) {
      debugPrint('FATAL_CRASH: $e');
      debugPrint('STACK_TRACE: $stack');
      if (!mounted) return;
      setState(() {
        _fatalError = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeAppState() async {
    debugPrint('APP_START: Initializing AppState...');
    final appState = AppState();
    await appState.init();
    debugPrint('APP_START: AppState initialized successfully.');

    if (!mounted) {
      appState.dispose();
      return;
    }

    // Re-create controller with the live updateLocalName callback so any
    // username change immediately re-broadcasts to mesh peers.
    final newController = MenuSettingsController(
      onDisplayNameChanged: appState.updateLocalName,
    );
    await newController.init();

    // Apply stored username into mesh advertising on startup.
    final storedUsername = newController.username;
    if (storedUsername != null && storedUsername.isNotEmpty) {
      appState.updateLocalName(storedUsername);
    }

    setState(() {
      _menuSettingsController = newController;
      _appState = appState;
      _showFirstSignIn = false;
      _isLoading = false;
    });
  }

  Future<void> _completeFirstSignIn(
    FirstSignInMethod method, {
    String? email,
  }) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    try {
      await _firstSignInService.complete(method: method, email: email);
      await _initializeAppState();
    } catch (e, stack) {
      debugPrint('FATAL_CRASH: $e');
      debugPrint('STACK_TRACE: $stack');
      if (!mounted) return;
      setState(() {
        _fatalError = e;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalError != null) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: Text(
              'Fatal Error: $_fatalError\nPlease restart the app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_appState != null) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _menuSettingsController),
          ChangeNotifierProvider.value(value: _appState!),
        ],
        child: MaterialApp(
          title: 'PeerChat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.darkTheme,
          home: const MainShell(),
        ),
      );
    }

    return MaterialApp(
      title: 'PeerChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: _isLoading
          ? const _BootstrapLoadingScreen()
          : _showFirstSignIn
              ? FirstSignInScreen(onComplete: _completeFirstSignIn)
              : const _BootstrapLoadingScreen(),
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

