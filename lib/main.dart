import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

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
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: JarvisColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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

  await memory.init();
  await sessionService.init();
  await ttsService.init();

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
  );
  await router.init(); 

  // Build chat provider
  final chatProvider = ChatProvider(
    router: router,
    sessionService: sessionService,
    ttsService: ttsService,
  );
  await chatProvider.init();

  final vibecodeController = VibeCodeController(router: router);
  final assignmentProvider = AssignmentProvider(router: router);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AIRouter>.value(value: router),
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ChangeNotifierProvider<OllamaProvider>.value(value: ollamaProvider),
        ChangeNotifierProvider<VibeCodeController>.value(value: vibecodeController),
        ChangeNotifierProvider<AssignmentProvider>.value(value: assignmentProvider),
        Provider<SecureStorageService>.value(value: secureStorage),
        Provider<MemoryService>.value(value: memory),
        Provider<SessionService>.value(value: sessionService),
        Provider<TtsService>.value(value: ttsService),
        Provider<FileProcessor>.value(value: fileProcessor),
        Provider<GoogleDocsService>.value(value: googleDocs),
      ],
      child: const JarvisApp(),
    ),
  );
}
