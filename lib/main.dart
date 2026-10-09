import 'package:flutter/material.dart';
import 'services/broadcaster_service.dart';
import 'services/scanner_service.dart';
import 'services/storage_service.dart';
import 'views/dashboard_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local Hive storage engine
  final storageService = StorageService();
  await storageService.init();

  // Initialize hardware services safely
  final broadcasterService = BroadcasterService();
  await broadcasterService.init();

  final scannerService = ScannerService();
  await scannerService.init();

  runApp(const AirDiaryApp());
}

class AirDiaryApp extends StatelessWidget {
  const AirDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirDiary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF1E2230),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF131622),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const DashboardView(),
    );
  }
}
