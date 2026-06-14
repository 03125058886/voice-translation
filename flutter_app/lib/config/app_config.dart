class AppConfig {
  // Change these to your backend server address
  static const String apiBaseUrl = 'https://voice-translation-production.up.railway.app';

  static String get wsBaseUrl =>
      apiBaseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

  // Web frontend URL (for invite links)
  static String get webBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    return '${uri.scheme}://${uri.host}:3000';
  }

  static String joinUrl(String sessionId) => '${webBaseUrl}/join/$sessionId';

  static String sessionWsUrl(String sessionId, String participantId) =>
      '$wsBaseUrl/ws/$sessionId/$participantId';

  static const int audioSampleRate = 16000;
  static const int audioChannels = 1;
  static const int audioChunkMs = 100;
}
