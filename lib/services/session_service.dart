import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/session.dart';
import '../../models/message.dart';

class SessionService {
  static const String _sessionsBox = 'sessions';
  static const String _messagesBox = 'messages';
  Box<Session>? _sessionsBox_;
  Box<Message>? _messagesBox_;
  final _uuid = const Uuid();

  Future<void> init() async {
    _sessionsBox_ = await Hive.openBox<Session>(_sessionsBox);
    _messagesBox_ = await Hive.openBox<Message>(_messagesBox);
  }

  Future<Session> createSession({String? title}) async {
    final session = Session(
      id: _uuid.v4(),
      title: title ?? 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _sessionsBox_?.put(session.id, session);
    return session;
  }

  List<Session> getAllSessions() {
    final sessions = _sessionsBox_?.values.toList() ?? [];
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  Session? getSession(String id) => _sessionsBox_?.get(id);

  Future<void> updateSession(Session session) async {
    await _sessionsBox_?.put(session.id, session);
  }

  Future<void> deleteSession(String id) async {
    await _sessionsBox_?.delete(id);
    // Also delete all messages in session
    final toDelete = _messagesBox_?.values
        .where((m) => m.sessionId == id)
        .map((m) => m.id)
        .toList() ?? [];
    for (final msgId in toDelete) {
      await _messagesBox_?.delete(msgId);
    }
  }

  Future<Message> addMessage(Message message) async {
    await _messagesBox_?.put(message.id, message);
    // Update session
    final session = _sessionsBox_?.get(message.sessionId);
    if (session != null) {
      final updated = session.copyWith(
        updatedAt: DateTime.now(),
        lastMessage: message.content.length > 80
            ? '${message.content.substring(0, 80)}...'
            : message.content,
        title: session.title == 'New Chat' && message.isUser
            ? (message.content.length > 40
                ? message.content.substring(0, 40)
                : message.content)
            : session.title,
      );
      await _sessionsBox_?.put(updated.id, updated);
    }
    return message;
  }

  Future<void> updateMessage(Message message) async {
    await _messagesBox_?.put(message.id, message);
  }

  List<Message> getMessages(String sessionId) {
    final msgs = _messagesBox_?.values
        .where((m) => m.sessionId == sessionId)
        .toList() ?? [];
    msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return msgs;
  }

  Future<void> clearMessages(String sessionId) async {
    final toDelete = _messagesBox_?.values
        .where((m) => m.sessionId == sessionId)
        .map((m) => m.id)
        .toList() ?? [];
    for (final msgId in toDelete) {
      await _messagesBox_?.delete(msgId);
    }
  }
}
