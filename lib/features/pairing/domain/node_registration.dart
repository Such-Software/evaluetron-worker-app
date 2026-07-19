class NodeRegistration {
  const NodeRegistration({
    required this.brainBaseUrl,
    required this.nodeId,
    required this.credentialId,
    required this.nodeName,
    required this.nodeToken,
    required this.roles,
  });

  final Uri brainBaseUrl;
  final String nodeId;
  final String credentialId;
  final String nodeName;
  final String nodeToken;
  final List<String> roles;

  Map<String, Object> toJson() => {
    'brainBaseUrl': brainBaseUrl.toString(),
    'nodeId': nodeId,
    'credentialId': credentialId,
    'nodeName': nodeName,
    'nodeToken': nodeToken,
    'roles': roles,
  };

  factory NodeRegistration.fromJson(Map<String, Object?> json) {
    final roles = json['roles'];
    return NodeRegistration(
      brainBaseUrl: Uri.parse(json['brainBaseUrl']! as String),
      nodeId: json['nodeId']! as String,
      credentialId: json['credentialId']! as String,
      nodeName: json['nodeName']! as String,
      nodeToken: json['nodeToken']! as String,
      roles: (roles! as List<Object?>).cast<String>(),
    );
  }
}
