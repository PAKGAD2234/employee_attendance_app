import 'package:employee_attendance_app/view/login_ui.dart';
import 'package:employee_attendance_app/view/splash_ui.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://zudwrubcrtgjtjragrkx.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp1ZHdydWJjcnRnanRqcmFncmt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2MDk2NDIsImV4cCI6MjA5MjE4NTY0Mn0.o2rMj_WvTGHNdNZ301vuX8UDwTanpGcKoYxJuP3G29k',
  );

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