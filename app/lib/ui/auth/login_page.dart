import 'package:flutter/material.dart';

import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../common/widgets.dart';

/// ログイン（S13）。成功したら true を返して閉じる
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.reason});
  final String? reason;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final ok = await AuthService.instance.login();
      if (!mounted) return;
      if (ok) {
        if (AuthService.instance.banned) {
          await infoDialog(context, title: 'このアカウントは利用停止されています', icon: I.alert_octagon, warn: true);
        }
        if (mounted) Navigator.pop(context, !AuthService.instance.banned);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'BANNED' => 'このアカウントは利用停止されています',
        'SIGNUP_LIMIT' => '本日はこれ以上アカウントを作成できません',
        _ => e.message,
      };
      await infoDialog(context, title: 'ログインできませんでした', body: msg, icon: I.warning, warn: true);
    } catch (e) {
      if (mounted) await infoDialog(context, title: 'ログインできませんでした', body: '$e', icon: I.warning, warn: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const TechMekuIcon(I.back), onPressed: () => Navigator.pop(context, false))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Center(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/brand/techmeku_icon_192.png', width: 84, height: 84))),
          const SizedBox(height: 16),
          const Center(child: Text('TechMeku にログイン', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          Center(child: Text(widget.reason ?? '投稿・いいね（投稿記事）・コメント・通報にはログインが必要です', style: TextStyle(color: c.muted), textAlign: TextAlign.center)),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : TechMekuIcon(I.log_in, color: c.bg, size: 20),
            label: const Text('Google でログイン'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [TechMekuIcon(I.shield, active: true, size: 20), const SizedBox(width: 8), const Text('保存しない情報', style: TextStyle(fontWeight: FontWeight.bold))]),
              const SizedBox(height: 8),
              const Text('・メールアドレス・氏名・プロフィール画像は保存しません\n'
                  '・サーバーには Google のユーザーIDをハッシュ化した値だけを保存します\n'
                  '・表示名はニックネーム（自動生成、あとで変更可）です\n'
                  '・興味タグ・ストック・いいね一覧は端末にだけ保存されます'),
            ]),
          ),
          const SizedBox(height: 16),
          Text('閲覧・DL・外部記事へのいいねは、ログインしなくても使えます。', style: TextStyle(color: c.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}
