import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:jarvis_ai/core/security/secure_storage_service.dart';

class McpAuthError implements Exception {
  final String message;
  McpAuthError(this.message);
  @override
  String toString() => 'McpAuthError: $message';
}

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      inputSchema: json['inputSchema'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
  }

  Map<String, dynamic> toGeminiSchema() {
    return {
      'name': name,
      'description': description,
      'parameters': _sanitizeSchema(inputSchema),
    };
  }

  static Map<String, dynamic> _sanitizeSchema(Map<String, dynamic> schema) {
    final sanitized = <String, dynamic>{};
    schema.forEach((key, value) {
      if (key == '\$schema' ||
          key == 'additionalProperties' ||
          key == 'default' ||
          key == 'title' ||
          key == 'format') {
        return;
      }
      if (value is Map<String, dynamic>) {
        sanitized[key] = _sanitizeSchema(value);
      } else if (value is List) {
        sanitized[key] = value
            .map((e) => e is Map<String, dynamic> ? _sanitizeSchema(e) : e)
            .toList();
      } else {
        sanitized[key] = value;
      }
    });
    return sanitized;
  }
}

class McpServer {
  final String id;
  final String url;
  String? authToken;
  String? sessionId;
  List<McpTool> tools = [];

  McpServer({
    required this.id,
    required this.url,
    this.authToken,
    this.sessionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'sessionId': sessionId,
      'tools': tools.map((t) => t.toJson()).toList(),
    };
  }

  factory McpServer.fromJson(Map<String, dynamic> json) {
    final server = McpServer(
      id: json['id'] ?? const Uuid().v4(),
      url: json['url'] ?? '',
      authToken: json['authToken'],
      sessionId: json['sessionId'],
    );
    if (json['tools'] != null) {
      server.tools = (json['tools'] as List)
          .map((t) => McpTool.fromJson(t))
          .toList();
    }
    return server;
  }

  Future<dynamic> _post(Map<String, dynamic> body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    if (sessionId != null && sessionId!.isNotEmpty) {
      headers['Mcp-Session-Id'] = sessionId!;
    }

    final resp = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw McpAuthError('Unauthorized');
    }

    if (resp.statusCode >= 400) {
      throw Exception('MCP Error (${resp.statusCode}): ${resp.body}');
    }

    // Capture Session ID if returned
    final returnedSessionId = resp.headers['mcp-session-id'];
    if (returnedSessionId != null && returnedSessionId.isNotEmpty) {
      sessionId = returnedSessionId;
    }

    if (resp.body.isEmpty) return {};

    final bodyText = resp.body.trim();

    // Parse SSE format — handles both simple `data: {...}` and
    // multi-line `event: message\ndata: {...}` used by many MCP servers
    if (bodyText.contains('data:')) {
      // Collect all data lines, take the last non-empty JSON one
      dynamic lastResult;
      for (final line in bodyText.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
          try {
            final parsed = jsonDecode(jsonStr);
            if (parsed is Map && parsed['error'] != null) {
              throw Exception(parsed['error']);
            }
            if (parsed is Map) {
              lastResult = parsed['result'] ?? parsed;
            }
          } catch (e) {
            if (e is Exception && e.toString().contains('MCP')) rethrow;
            // Incomplete JSON chunk — skip
          }
        }
      }
      if (lastResult != null) return lastResult;
    }

    // Fallback to raw JSON
    try {
      final parsed = jsonDecode(bodyText);
      if (parsed is Map && parsed['error'] != null) throw Exception(parsed['error']);
      if (parsed is Map) return parsed['result'] ?? parsed;
      return {};
    } catch (e) {
      // Body is not JSON (e.g. plain 200 OK text from notifications) — treat as success
      return {};
    }
  }

  static String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String _codeChallengeS256(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Auto-connect: Tries plain connection, falls back to OAuth if 401
  static Future<McpServer> connect(
    String url, {
    String? token,
    String? id,
  }) async {
    final server = McpServer(
      id: id ?? const Uuid().v4(),
      url: url,
      authToken: token,
    );

    try {
      await server._handshake();
      return server;
    } on McpAuthError catch (_) {
      // 401 triggered, auto fallback to OAuth flow
      return await connectWithOAuth(server);
    }
  }

  Future<void> _handshake({String protocolVersion = '2025-03-26'}) async {
    // 1. Initialize Handshake — try newer protocol first
    try {
      await _post({
        "jsonrpc": "2.0",
        "method": "initialize",
        "id": const Uuid().v4(),
        "params": {
          "protocolVersion": protocolVersion,
          "capabilities": {"tools": {}},
          "clientInfo": {"name": "JARVIS", "version": "2.0.0"},
        },
      });
    } catch (e) {
      // If newer protocol rejected, fall back to 2024-11-05
      if (protocolVersion != '2024-11-05') {
        await _handshake(protocolVersion: '2024-11-05');
        return;
      }
      rethrow;
    }

    // 2. Notifications/initialized — fire-and-forget, some servers reject it
    // Per MCP spec §4.1: notifications have no id and no response expected
    try {
      await _post({"jsonrpc": "2.0", "method": "notifications/initialized"});
    } catch (_) {
      // Intentionally ignored — not all servers implement this
    }

    // 3. Fetch Tools
    final toolsData = await _post({
      "jsonrpc": "2.0",
      "method": "tools/list",
      "id": const Uuid().v4(),
    });

    // Handle both {tools: [...]} and {result: {tools: [...]}} wrappings
    dynamic rawList = toolsData;
    if (rawList is Map && rawList['tools'] == null && rawList['result'] != null) {
      rawList = rawList['result'];
    }
    final toolsList = (rawList is Map ? rawList['tools'] : null) as List<dynamic>? ?? [];
    tools = toolsList.map((t) => McpTool.fromJson(t as Map<String, dynamic>)).toList();
  }

  static Future<McpServer> connectWithOAuth(McpServer server) async {
    final mcpUrl = server.url;

    // Step 1: probe server OAuth metadata
    // Normalize URL — remove trailing slash, then append /.well-known path
    final baseUrl = mcpUrl.endsWith('/')
        ? mcpUrl.substring(0, mcpUrl.length - 1)
        : mcpUrl;
    final metaUrl = '$baseUrl/.well-known/oauth-authorization-server';
    final metaResp = await http
        .get(Uri.parse(metaUrl))
        .timeout(const Duration(seconds: 10));
    if (metaResp.statusCode >= 400) {
      throw Exception(
        'Server requires authentication but lacks OAuth metadata endpoint (tried $metaUrl).',
      );
    }
    final meta = jsonDecode(metaResp.body);

    String? clientId = meta['client_id'];

    if (clientId == null) {
      if (meta['registration_endpoint'] != null) {
        final regResp = await http.post(
          Uri.parse(meta['registration_endpoint']),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_name': 'JARVIS',
            'redirect_uris': ['jarvis://mcp-callback'],
            'grant_types': ['authorization_code'],
            'response_types': ['code'],
            'token_endpoint_auth_method': 'none',
          }),
        );
        if (regResp.statusCode >= 400) {
          throw Exception(
            'Dynamic client registration failed: ${regResp.body}',
          );
        }
        clientId = jsonDecode(regResp.body)['client_id'];
      } else {
        throw Exception(
          'This server needs manual app registration — no dynamic registration support.',
        );
      }
    }

    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeS256(verifier);

    final authUrl = Uri.parse(meta['authorization_endpoint']).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': 'jarvis://mcp-callback',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );

    // Trigger system browser for OAuth login
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: 'jarvis',
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      throw Exception('OAuth login failed: No authorization code returned');
    }

    // Exchange code for token
    final tokenResp = await http.post(
      Uri.parse(meta['token_endpoint']),
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': 'jarvis://mcp-callback',
        'code_verifier': verifier,
        'client_id': clientId,
      },
    );

    if (tokenResp.statusCode >= 400) {
      throw Exception('OAuth token exchange failed');
    }

    final accessToken = jsonDecode(tokenResp.body)['access_token'];
    server.authToken = accessToken;

    final secureStorage = SecureStorageService();
    await secureStorage.saveMcpToken(server.id, accessToken);

    // Resume handshake with valid token
    await server._handshake();

    return server;
  }

  /// Calls a tool on the remote MCP server
  Future<Map<String, dynamic>> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _post({
      "jsonrpc": "2.0",
      "method": "tools/call",
      "params": {"name": toolName, "arguments": arguments},
      "id": const Uuid().v4(),
    });
    return result as Map<String, dynamic>? ?? {};
  }
}
