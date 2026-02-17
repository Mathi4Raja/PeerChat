import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/app_state.dart';
import 'src/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('APP_START: Initializing AppState...');
  final appState = AppState();
  try {
    await appState.init();
    debugPrint('APP_START: AppState initialized successfully.');
    runApp(MyApp(appState: appState));
  } catch (e, stack) {
    debugPrint('FATAL_CRASH: $e');
    debugPrint('STACK_TRACE: $stack');
    // Fallback UI or silent fail? For now, we want to see this in logs.
    runApp(MaterialApp(
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
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
