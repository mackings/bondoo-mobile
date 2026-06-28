class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://bondoo-api.onrender.com',
  );

  static const agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: 'd454d5abab694b20ae57c6a5b4953e0a',
  );

  static const agoraToken = String.fromEnvironment('AGORA_TOKEN');
}
