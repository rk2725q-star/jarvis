import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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
      if (key == '\$schema' || key == 'additionalProperties' || key == 'default' || key == 'title' || key == 'format') {
        return;
      }
      if (value is Map<String, dynamic>) {
        sanitized[key] = _sanitizeSchema(value);
      } else if (value is List) {
        sanitized[key] = value.map((e) => e is Map<String, dynamic> ? _sanitizeSchema(e) : e).toList();
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
  final String? authToken;
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
      'authToken': authToken,
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
      server.tools = (json['tools'] as List).map((t) => McpTool.fromJson(t)).toList();
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

    final resp = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

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
    
    // Parse SSE format if present
    if (bodyText.startsWith('data:')) {
      for (final line in bodyText.split('\n')) {
        if (line.trim().startsWith('data:')) {
          final jsonStr = line.substring(line.indexOf('data:') + 5).trim();
          if (jsonStr.isNotEmpty) {
            final parsed = jsonDecode(jsonStr);
            if (parsed['error'] != null) throw Exception(parsed['error']);
            return parsed['result'] ?? {};
          }
        }
      }
    }
    
    // Fallback to raw JSON
    final parsed = jsonDecode(bodyText);
    if (parsed['error'] != null) throw Exception(parsed['error']);
    return parsed['result'] ?? {};
  }

  /// Fetches tools from the remote MCP server via JSON-RPC
  static Future<McpServer> connect(String url, {String? token}) async {
    final server = McpServer(id: const Uuid().v4(), url: url, authToken: token);

    // 1. Initialize Handshake
    await server._post({
      "jsonrpc": "2.0",
      "method": "initialize",
      "id": const Uuid().v4(),
      "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {
          "name": "jarvis-client",
          "version": "1.0.0"
        }
      }
    });

    // 2. Notifications/initialized (Required by MCP spec)
    await server._post({
      "jsonrpc": "2.0",
      "method": "notifications/initialized"
    });

    // 3. Fetch Tools
    final toolsData = await server._post({
      "jsonrpc": "2.0",
      "method": "tools/list",
      "id": const Uuid().v4(),
    });

    final toolsList = toolsData['tools'] as List<dynamic>? ?? [];
    server.tools = toolsList.map((t) => McpTool.fromJson(t)).toList();
    return server;
  }

  /// Calls a tool on the remote MCP server
  Future<Map<String, dynamic>> callTool(String toolName, Map<String, dynamic> arguments) async {
    final result = await _post({
      "jsonrpc": "2.0",
      "method": "tools/call",
      "params": {
        "name": toolName,
        "arguments": arguments,
      },
      "id": const Uuid().v4(),
    });
    return result as Map<String, dynamic>? ?? {};
  }
}
