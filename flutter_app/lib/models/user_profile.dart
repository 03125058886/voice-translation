class UserProfile {
  final String name;
  final String language;
  final String phone;

  const UserProfile({
    required this.name,
    required this.language,
    required this.phone,
  });

  UserProfile copyWith({
    String? name,
    String? language,
    String? phone,
  }) =>
      UserProfile(
        name: name ?? this.name,
        language: language ?? this.language,
        phone: phone ?? this.phone,
      );
}
