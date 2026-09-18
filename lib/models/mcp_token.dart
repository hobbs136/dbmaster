//! Wire models for the Server's MCP personal-token REST API
//! (`/api/mcp/tokens`, dbx-response T04b / D7). Mirrors the token
//! lifecycle on the server: create returns the plaintext exactly once;
//! list rows only ever carry the display prefix.

/// A live token row as returned by `GET /api/mcp/tokens` — **no secret
/// material**, only the short display prefix (`dbm_mcp_9f2a…`).
class McpTokenInfo {
  final String id;
  final String name;
  final String tokenPrefix;
  final String createdAt;
  final String? lastUsedAt;

  const McpTokenInfo({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory McpTokenInfo.fromJson(Map<String, dynamic> json) {
    return McpTokenInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      tokenPrefix: json['token_prefix'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      lastUsedAt: json['last_used_at'] as String?,
    );
  }
}

/// The one-time create response from `POST /api/mcp/tokens` — the only
/// place the full plaintext appears. Held in dialog state long enough to
/// copy, never written to any client persistence.
class McpTokenCreated {
  final String id;
  final String name;
  final String token;
  final String createdAt;

  const McpTokenCreated({
    required this.id,
    required this.name,
    required this.token,
    required this.createdAt,
  });

  factory McpTokenCreated.fromJson(Map<String, dynamic> json) {
    return McpTokenCreated(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      token: json['token'] as String,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
