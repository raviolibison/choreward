import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'setup_screen.dart';
import 'parent_screen.dart';
import 'child_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Choreward',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
        ).copyWith(
          secondary: const Color(0xFFF59E0B),
          error: const Color(0xFFEF4444),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF0FDF4),
        textTheme: GoogleFonts.bricolageGrotesqueTextTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF2D6A4F),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.bricolageGrotesque(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D6A4F),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2D6A4F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2D6A4F),
            textStyle: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 2),
          ),
          floatingLabelStyle: const TextStyle(color: Color(0xFF2D6A4F)),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF2D6A4F),
          foregroundColor: Colors.white,
          shape: CircleBorder(),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: const Color(0xFF2D6A4F),
          unselectedItemColor: Colors.grey[500],
          backgroundColor: Colors.white,
          elevation: 8,
          selectedLabelStyle: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: GoogleFonts.bricolageGrotesque(fontSize: 12),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF2D6A4F),
          thumbColor: Color(0xFF2D6A4F),
          valueIndicatorColor: Color(0xFF2D6A4F),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFBBF7D0)),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1B4332),
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const RoleRouter();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (FirebaseAuth.instance.currentUser == null) {
          return const LoginScreen();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        final householdIds = data?['householdIds'] as List?;
        if (data == null || householdIds == null || householdIds.isEmpty) {
          return const SetupScreen();
        }

        if (data['role'] == 'parent') {
          return const ParentScreen();
        }

        return const ChildScreen();
      },
    );
  }
}
