import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'src/app_state.dart';
import 'src/screens/main_shell.dart';
import 'src/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive dark status/nav bars
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDeep,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  debugPrint('APP_START: Initializing AppState...');
  final appState = AppState();
  try {
    await appState.init();
    debugPrint('APP_START: AppState initialized successfully.');
    runApp(MyApp(appState: appState));
  } catch (e, stack) {
    debugPrint('FATAL_CRASH: $e');
    debugPrint('STACK_TRACE: $stack');
    runApp(MaterialApp(
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(child: Text('Fatal Error: $e\nPlease restart the app.')),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  final AppState appState;
  const MyApp({required this.appState, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        title: 'PeerChat Secure',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: AppTheme.darkTheme,
        home: const MainShell(),
      ),
    );
  }
}
