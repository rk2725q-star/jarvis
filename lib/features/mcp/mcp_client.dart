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

  Map<String, dynamic> toGeminiSchema() {
    return {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    };
  }
}

class McpServer {
  final String id;
  final String url;
  final String? authToken;
  List<McpTool> tools = [];

  McpServer({
    required this.id,
    required this.url,
    this.authToken,
  });

  /// Fetches tools from the remote MCP server via JSON-RPC
  static Future<McpServer> connect(String url, {String? token}) async {
    final server = McpServer(id: const Uuid().v4(), url: url, authToken: token);
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final reqBody = jsonEncode({
      "jsonrpc": "2.0",
      "method": "tools/list",
      "id": 1,
    });

    final resp = await http.post(
      Uri.parse(url),
      headers: headers,
      body: reqBody,
    );

    if (resp.statusCode != 200) {
      throw Exception('Failed to connect to MCP Server ($url): ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    if (data['error'] != null) {
      throw Exception('MCP Error: ${data['error']}');
    }

    final toolsData = data['result']?['tools'] as List<dynamic>? ?? [];
    server.tools = toolsData.map((t) => McpTool.fromJson(t)).toList();
    return server;
  }

  /// Calls a tool on the remote MCP server
  Future<Map<String, dynamic>> callTool(String toolName, Map<String, dynamic> arguments) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    final reqBody = jsonEncode({
      "jsonrpc": "2.0",
      "method": "tools/call",
      "params": {
        "name": toolName,
        "arguments": arguments,
      },
      "id": 2, // arbitrary ID
    });

    final resp = await http.post(
      Uri.parse(url),
      headers: headers,
      body: reqBody,
    );

    if (resp.statusCode != 200) {
      throw Exception('Tool Call Failed: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    if (data['error'] != null) {
      throw Exception('MCP Error executing tool $toolName: ${data['error']}');
    }

    return data['result'] ?? {};
  }
}
