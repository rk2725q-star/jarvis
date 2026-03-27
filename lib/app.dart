import 'package:flutter/material.dart';
import 'theme/jarvis_theme.dart';
import 'features/chat/chat_screen.dart';

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS AI',
      debugShowCheckedModeBanner: false,
      theme: JarvisTheme.dark,
      home: const ChatScreen(),
    );
  }
}
