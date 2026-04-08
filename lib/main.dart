import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'screens/computer_login_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mobile_dashboard.dart';
import 'screens/cashier_mobile_dashboard.dart';
import 'providers/theme_provider.dart';
import 'providers/data_providers.dart';
import 'utils/app_colors.dart';
import 'services/sync_service.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/local_database.dart';
import 'dart:io';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

late SharedPreferences prefs;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bypass SSL certificate verification for desktop/emulators facing HandshakeException
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    HttpOverrides.global = MyHttpOverrides();
  }
  prefs = await SharedPreferences.getInstance();

  // Initialize SQLite Local DB
  await LocalDatabase.instance.database;

  await Supabase.initialize(
    url: 'https://bwkhkwtolzsmebxkpmht.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3a2hrd3RvbHpzbWVieGtwbWh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwMDg5MzgsImV4cCI6MjA4OTU4NDkzOH0.SL0gtsfpaM741naIyFX21fCSECAzRxqbopn0CiEw4vo',
  );

  final container = ProviderContainer();
  final syncService = container.read(syncServiceProvider);

  // Initial Sync: Upload offline data first, then download new updates
  syncService.syncUp();
  syncService.syncDown();

  // Smart background sync: every 30 s, silently push any pending data.
  // Only calls syncUp when there is actually something to upload, so it
  // has no visible effect on the user when everything is already in sync.
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (await syncService.hasUnsyncedData()) {
      syncService.syncUp();
    }
  });

  // Pull remote changes (products, prices, users) every 2 minutes.
  Timer.periodic(const Duration(minutes: 2), (timer) {
    syncService.syncDown();
  });

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(authProvider);

    return MaterialApp(
      title: 'نظام الكاشير',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'IQ')],
      locale: const Locale('ar', 'IQ'),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.9)),
          child: child!,
        );
      },
      home: SessionMonitor(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 800) {
              if (user == null) {
                return const LoginScreen();
              } else if (user.role == 'cashier') {
                return const CashierMobileDashboardScreen();
              } else {
                return const MobileDashboard();
              }
            } else {
              return user == null
                  ? const ComputerLoginScreen()
                  : const PosScreen();
            }
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    var baseTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
    );

    final textTheme = baseTheme.textTheme.copyWith(
      displayLarge: baseTheme.textTheme.displayLarge?.copyWith(fontSize: 48),
      displayMedium: baseTheme.textTheme.displayMedium?.copyWith(fontSize: 40),
      displaySmall: baseTheme.textTheme.displaySmall?.copyWith(fontSize: 32),
      headlineLarge: baseTheme.textTheme.headlineLarge?.copyWith(fontSize: 28),
      headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(fontSize: 24),
      headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(fontSize: 20),
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(fontSize: 20),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(fontSize: 16),
      titleSmall: baseTheme.textTheme.titleSmall?.copyWith(fontSize: 14),
      bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(fontSize: 16),
      bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(fontSize: 14),
      bodySmall: baseTheme.textTheme.bodySmall?.copyWith(fontSize: 12),
    );

    return baseTheme.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(textTheme),
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0B132B)
          : const Color(0xFFF8FAFC),
    );
  }
}

class SessionMonitor extends ConsumerWidget {
  final Widget child;
  const SessionMonitor({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = ref.watch(currentSessionIdProvider);
    final user = ref.read(authProvider);

    if (sessionId != null && user != null) {
      final supabase = ref.read(supabaseProvider);
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('sessions')
            .stream(primaryKey: ['id'])
            .eq('id', sessionId),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            bool shouldLogout = false;
            if (snapshot.data!.isEmpty) {
              shouldLogout = true;
            } else {
              final session = snapshot.data!.first;
              final isActive =
                  session['is_active'] == true || session['is_active'] == 1;
              if (!isActive) shouldLogout = true;
            }

            if (shouldLogout) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(authProvider.notifier).logout();
                ref.read(currentSessionIdProvider.notifier).set(null);
              });
            }
          }
          return child;
        },
      );
    }

    return child;
  }
}
