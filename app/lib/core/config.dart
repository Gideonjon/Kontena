/// Build-time config. Override with --dart-define=API_URL=https://api.example.com
class Config {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.kontena.app');
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://kontena.app');
  static const appUrl = String.fromEnvironment('APP_URL', defaultValue: 'https://kontena.app/app');
}
