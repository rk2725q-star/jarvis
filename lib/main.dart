/*
 * Copyright 2024
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;

import 'core/memory/memory_service.dart';
import 'core/router/ai_router.dart';
import 'core/security/secure_storage_service.dart';
import 'core/file_processor/file_processor.dart';
import 'features/chat/chat_provider.dart';
import 'providers/ollama_provider.dart';
import 'models/memory_item.dart';
import 'models/message.dart';
import 'models/session.dart';
import 'services/session_service.dart';
import 'services/tts_service.dart';
import 'services/notification_service.dart';
import 'theme/jarvis_theme.dart';
import 'features/vibecode/vibecode_controller.dart';
import 'services/google_docs_service.dart';
import 'features/assignment/assignment_provider.dart';
import 'features/integrations/integrations_provider.dart';
import 'services/skill_service.dart';
import 'package:flutter_file_view/flutter_file_view.dart';
import 'package:audio_service/audio_service.dart';
import 'features/youtube/yt_audio_handler.dart';
import 'features/youtube/youtube_download_manager.dart';
import 'app.dart';

late YTAudioHandler ytAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init background audio service (YouTube Premium-style: plays on home/lock,
  // stops when user clears app from recents)
  ytAudioHandler = await AudioService.init(
    builder: () => YTAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.jarvis.yt.channel.audio',
      androidNotificationChannelName: 'YouTube Background Play',
      androidNotificationChannelDescription:
          'Keeps YouTube audio playing in background',
      androidStopForegroundOnPause:
          false, // keep foreground service alive on pause
      notificationColor: Color(0xFFFF0000),
    ),
  );

  // Pre-initialize X5 engine (non-blocking)
  FlutterFileView.init();

  // System UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: JarvisColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Hive
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MessageAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(SessionAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(MemoryItemAdapter());

  // Initialize services
  final secureStorage = SecureStorageService();
  final memory = MemoryService();
  final sessionService = SessionService();
  final ttsService = TtsService();
  final fileProcessor = FileProcessor();
  final googleDocs = GoogleDocsService();
  final skillService = SkillService();

  await memory.init();
  await sessionService.init();
  await ttsService.init();
  await skillService.init();

  final ollamaProvider = OllamaProvider();
  await ollamaProvider.init();

  // Initialize notifications for background routines
  await NotificationService().init();

  // Build router
  final router = AIRouter(
    secureStorage: secureStorage,
    memory: memory,
    fileProcessor: fileProcessor,
    ollamaService: ollamaProvider.service,
    googleDocs: googleDocs,
    skillService: skillService,
  );
  await router.init();

  // Build integrations provider FIRST (needed by chatProvider)
  final integrationsProvider = IntegrationsProvider();
  await integrationsProvider.init();

  // Build chat provider
  final chatProvider = ChatProvider(
    router: router,
    sessionService: sessionService,
    ttsService: ttsService,
    integrationsProvider: integrationsProvider,
  );
  await chatProvider.init();

  final vibecodeController = VibeCodeController(router: router);
  final assignmentProvider = AssignmentProvider(router: router);

  runApp(
    rp.ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AIRouter>.value(value: router),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
          ChangeNotifierProvider<OllamaProvider>.value(value: ollamaProvider),
          ChangeNotifierProvider<VibeCodeController>.value(
            value: vibecodeController,
          ),
          ChangeNotifierProvider<AssignmentProvider>.value(
            value: assignmentProvider,
          ),
          ChangeNotifierProvider<IntegrationsProvider>.value(
            value: integrationsProvider,
          ),
          ChangeNotifierProvider<SkillService>.value(value: skillService),
          ChangeNotifierProvider<YTDownloadProvider>(
            create: (_) => YTDownloadProvider(),
          ),
          Provider<SecureStorageService>.value(value: secureStorage),
          Provider<MemoryService>.value(value: memory),
          Provider<SessionService>.value(value: sessionService),
          Provider<TtsService>.value(value: ttsService),
          Provider<FileProcessor>.value(value: fileProcessor),
          Provider<GoogleDocsService>.value(value: googleDocs),
          Provider<SkillService>.value(value: skillService),
        ],
        child: const JarvisApp(),
      ),
    ),
  );
}
