import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure the global audio session once at startup so AVPlayer on iOS can
  // create AVPlayerItems without failing. playAndRecord + defaultToSpeaker is
  // the standard category for messaging apps that both record and play audio.
  await AudioPlayer.global.setAudioContext(AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: {AVAudioSessionOptions.defaultToSpeaker},
    ),
    android: AudioContextAndroid(
      audioFocus: AndroidAudioFocus.gain,
      usageType: AndroidUsageType.media,
      contentType: AndroidContentType.music,
    ),
  ));
  runApp(const ProviderScope(child: BondooApp()));
}

class BondooApp extends StatelessWidget {
  const BondooApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BONDOO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}
