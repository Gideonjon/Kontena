/// Build-time config. Override with --dart-define=API_URL=https://api.example.com
class Config {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://kontena-api.purpose-money-api.workers.dev');
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://kontena.store');
  static const appUrl = String.fromEnvironment('APP_URL', defaultValue: 'https://kontena.store/app');
}
