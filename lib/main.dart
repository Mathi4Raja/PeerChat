import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'src/app_state.dart';
import 'src/screens/first_sign_in_screen.dart';
import 'src/screens/main_shell.dart';
import 'src/services/first_sign_in_service.dart';
import 'src/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  AppState? _appState;
  Object? _fatalError;
  bool _isLoading = true;
  bool _showFirstSignIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
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
    setState(() {
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
      return ChangeNotifierProvider.value(
        value: _appState!,
        child: MaterialApp(
          title: 'PeerChat Secure',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.darkTheme,
          home: const MainShell(),
        ),
      );
    }

    return MaterialApp(
      title: 'PeerChat Secure',
      debugShowCheckedModeBanner: false,
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

