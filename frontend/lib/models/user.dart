class User {
  final String id;
  final String username;
  final String email;
  final String role;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    this.email = '',
    required this.role,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String? ?? '',
        role: json['role'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'role': role,
        'created_at': createdAt.toIso8601String(),
      };

  bool hasAtLeastRole(String requiredRole) {
    const hierarchy = {
      'super_admin': 6,
      'system_admin': 5,
      'template_admin': 4,
      'project_admin': 3,
      'editor': 2,
      'viewer': 1,
    };
    return (hierarchy[role] ?? 0) >= (hierarchy[requiredRole] ?? 0);
  }
}
