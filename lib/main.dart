import 'package:employee_attendance_app/view/landing_ui.dart';
import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:employee_attendance_app/view/splash_ui.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:employee_attendance_app/services/sheets_client.dart';
import 'package:employee_attendance_app/services/sheets_config.dart';
import 'package:employee_attendance_app/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SheetsClient.initialize(
    url: kSheetsUrl,
    apiKey: kSheetsApiKey,
  );
  SupabaseService().initialize(SheetsClient.instance);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.promptTextTheme(),
      ),
      home: SplashUi(),
    );
  }
}