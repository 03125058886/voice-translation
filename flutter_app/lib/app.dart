import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

class VoiceTranslationApp extends ConsumerWidget {
  const VoiceTranslationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bg950,
    ));

    final profile = ref.watch(authProvider);

    return MaterialApp(
      title: 'VoiceTranslate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: profile != null
          ? HomeScreen(
              initialName: profile.name,
              initialLanguage: profile.language,
              photoUrl: null,
            )
          : const LoginScreen(),
    );
  }
}
