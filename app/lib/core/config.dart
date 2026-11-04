/// アプリ全体の設定値。
///
/// `--dart-define=API_BASE=http://10.0.2.2:8787` でローカルの wrangler dev に向けられる。
class AppConfig {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://techmeku-api.ryome-blog.workers.dev');

  /// OAuth Web クライアントID（serverClientId）。ID トークンの aud になる。公開されてよい値。
  static const googleServerClientId = '294650983462-ritiia32pi9q3j1vqesgedvu7tf3oljo.apps.googleusercontent.com';

  static const termsUrl = 'https://github.com/ryomeblog/tech-meku/blob/main/doc/terms.md';
  static const privacyUrl = 'https://github.com/ryomeblog/tech-meku/blob/main/doc/privacy.md';
  static const appVersion = '0.1.0';
}
