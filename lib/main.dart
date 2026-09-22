import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/app_config.dart';
import 'core/router.dart';
import 'core/theme_provider.dart';
import 'core/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );

    // Automatically sync device FCM token whenever user signs in or restores session
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        NotificationService.instance.syncTokenWithSupabase();
      }
    });
  }

  // Initialize Firebase Cloud Messaging push service
  await NotificationService.instance.initialize();

  runApp(
    ProviderScope(
      child: AppConfig.isConfigured ? MyApp() : ConfigurationRequiredApp(),
    ),
  );
}

class ConfigurationRequiredApp extends StatelessWidget {
  const ConfigurationRequiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jaldi',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Jaldi setup required')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: SelectableText(
            'Configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY with --dart-define before running Jaldi.',
          ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    NotificationService.instance.setRouter(router);

    return MaterialApp.router(
      title: 'Jaldi',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
