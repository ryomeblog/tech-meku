import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/settings.dart';
import '../../core/techmeku_icon.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../models/models.dart';
import '../../services/api.dart';
import '../../services/auth.dart';
import '../../services/scheduler.dart';
import '../../services/stock.dart';
import '../auth/login_page.dart';
import '../common/widgets.dart';
import '../tags/tag_select_page.dart';
import 'downloaded_list_page.dart';

/// 設定（S14、doc/design.md 2.17）
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TmColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Row(children: [TechMekuIcon(I.settings, size: 20), SizedBox(width: 8), Text('設定', style: TextStyle(fontSize: 17))])),
      body: ListenableBuilder(
        listenable: Listenable.merge([Settings.instance, AuthService.instance, StockRepo.instance]),
        builder: (context, _) {
          final s = Settings.instance;
          final auth = AuthService.instance;
          return ListView(children: [
            const SectionTitle('興味タグ'),
            ListTile(
              leading: const TechMekuIcon(I.tag),
              title: const Text('興味タグの編集'),
              subtitle: Text(s.interestTags.isEmpty ? '未設定（AI＋ランダム2つ）' : s.interestTags.map((t) => '#$t').join(' '), maxLines: 2),
              trailing: Text('${s.interestTags.length}/10', style: TextStyle(color: c.muted)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagSelectPage())),
            ),
            const SectionTitle('DL'),
            ListTile(
              leading: const TechMekuIcon(I.download),
              title: const Text('取得件数（サイトごと）'),
              subtitle: const Text('Qiita は最大20件'),
              trailing: DropdownButton<int>(
                value: s.fetchCount,
                underline: const SizedBox(),
                items: const [10, 30, 50].map((v) => DropdownMenuItem(value: v, child: Text('$v件'))).toList(),
                onChanged: (v) => s.setFetchCount(v!),
              ),
            ),
            for (final site in SourceType.external)
              SwitchListTile(
                secondary: const TechMekuIcon(I.layers),
                title: Text(site.label),
                subtitle: s.failures(site) >= 3 ? Text('取得できません（仕様変更の可能性）', style: TextStyle(color: c.warn, fontSize: 12)) : null,
                value: s.siteEnabled(site),
                onChanged: (v) => s.setSiteEnabled(site, v),
              ),
            SwitchListTile(
              secondary: const TechMekuIcon(I.refresh),
              title: const Text('定期自動DL'),
              subtitle: const Text('1日1回、興味タグの人気記事に入れ替えます'),
              value: s.autoDl,
              onChanged: (v) async {
                await s.setAutoDl(v);
                await Scheduler.apply();
              },
            ),
            SwitchListTile(
              secondary: const TechMekuIcon(I.wifi),
              title: const Text('Wi-Fi 時のみ'),
              subtitle: const Text('定期自動DLだけに効きます（自動補充は通信の種類に関わらず実行）'),
              value: s.wifiOnly,
              onChanged: s.autoDl
                  ? (v) async {
                      await s.setWifiOnly(v);
                      await Scheduler.apply();
                    }
                  : null,
            ),
            const SectionTitle('ストレージ'),
            FutureBuilder<int>(
              future: StockRepo.instance.totalBytes(),
              builder: (_, snap) {
                final used = snap.data ?? 0;
                return ListTile(
                  leading: const TechMekuIcon(I.database),
                  title: const Text('使用量'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(
                      value: (used / s.storageLimitBytes).clamp(0, 1),
                      color: used > s.storageLimitBytes ? c.warn : c.active,
                      backgroundColor: c.card,
                    ),
                  ),
                  trailing: Text('${formatBytes(used)} / ${s.storageLimitGb} GB', style: TextStyle(color: used > s.storageLimitBytes ? c.warn : c.muted)),
                );
              },
            ),
            ListTile(
              leading: const TechMekuIcon(I.sliders),
              title: const Text('容量上限'),
              subtitle: const Text('超えたら警告を出します（DL は続行）'),
              trailing: DropdownButton<int>(
                value: s.storageLimitGb,
                underline: const SizedBox(),
                items: const [1, 3, 5, 10].map((v) => DropdownMenuItem(value: v, child: Text('$v GB'))).toList(),
                onChanged: (v) => s.setStorageLimitGb(v!),
              ),
            ),
            ListTile(
              leading: const TechMekuIcon(I.library),
              title: const Text('DLしたもの'),
              subtitle: const Text('全件（キャッシュを含む）。削除できます'),
              trailing: const TechMekuIcon(I.chevron_right, muted: true),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadedListPage())),
            ),
            ListTile(
              leading: TechMekuIcon(I.trash, color: c.warn),
              title: Text('全削除', style: TextStyle(color: c.warn)),
              onTap: () async {
                if (await confirmDialog(context, title: 'DLした記事をすべて削除しますか？', body: 'ストックとキャッシュがすべて消えます。いいね一覧は残ります。', ok: '全削除', danger: true, icon: I.trash)) {
                  await StockRepo.instance.deleteAll();
                  if (context.mounted) showSnack(context, '削除しました');
                }
              },
            ),
            const SectionTitle('表示'),
            ListTile(
              leading: const TechMekuIcon(I.preview),
              title: const Text('テーマ'),
              trailing: DropdownButton<ThemeMode>(
                value: s.themeMode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('システム')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('ライト')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('ダーク')),
                ],
                onChanged: (v) => s.setThemeMode(v!),
              ),
            ),
            ListTile(
              leading: const TechMekuIcon(I.sliders),
              title: const Text('文字サイズ'),
              subtitle: Slider(value: s.textScale, min: 0.8, max: 1.6, divisions: 8, label: '${(s.textScale * 100).round()}%', onChanged: s.setTextScale),
            ),
            const SectionTitle('アカウント'),
            if (!auth.loggedIn)
              ListTile(
                leading: const TechMekuIcon(I.log_in),
                title: const Text('ログイン'),
                subtitle: const Text('Google アカウントでログイン'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage())),
              )
            else ...[
              ListTile(
                leading: const TechMekuIcon(I.user),
                title: const Text('ニックネーム'),
                subtitle: Text(auth.nickname ?? ''),
                trailing: const TechMekuIcon(I.edit, size: 18),
                onTap: () => _editNickname(context),
              ),
              ListTile(
                leading: const TechMekuIcon(I.log_out),
                title: const Text('ログアウト'),
                onTap: () async {
                  if (await confirmDialog(context, title: 'ログアウトしますか？', ok: 'ログアウト', icon: I.log_out)) await auth.logout();
                },
              ),
              ListTile(
                leading: TechMekuIcon(I.user_x, color: c.warn),
                title: Text('アカウント削除', style: TextStyle(color: c.warn)),
                subtitle: const Text('投稿・コメント・いいねをすべて削除します'),
                onTap: () => _deleteAccount(context),
              ),
            ],
            const SectionTitle('その他'),
            ListTile(leading: const TechMekuIcon(I.file_text), title: const Text('利用規約'), trailing: const TechMekuIcon(I.external_link, size: 18), onTap: () => _open(AppConfig.termsUrl)),
            ListTile(leading: const TechMekuIcon(I.shield), title: const Text('プライバシーポリシー'), trailing: const TechMekuIcon(I.external_link, size: 18), onTap: () => _open(AppConfig.privacyUrl)),
            ListTile(
              leading: const TechMekuIcon(I.list),
              title: const Text('ライセンス'),
              onTap: () => showLicensePage(context: context, applicationName: 'TechMeku', applicationVersion: AppConfig.appVersion),
            ),
            ListTile(leading: const TechMekuIcon(I.info), title: const Text('バージョン'), trailing: Text(AppConfig.appVersion, style: TextStyle(color: c.muted))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('記事の著作権は各執筆者に帰属します。外部記事はこの端末にだけ保存され、TechMeku のサーバーには送られません。', style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Future<void> _editNickname(BuildContext context) async {
    final ctl = TextEditingController(text: AuthService.instance.nickname);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ニックネーム', style: TextStyle(fontSize: 17)),
        content: TextField(controller: ctl, maxLength: 20, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    try {
      await AuthService.instance.updateNickname(v);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    if (!await confirmDialog(
      context,
      title: 'アカウントを削除しますか？',
      body: '投稿・コメント・いいねがすべて即座に削除されます。延長済みの期限は戻りません。端末のストックといいね一覧は残ります。',
      ok: '削除する',
      danger: true,
      icon: I.alert_octagon,
    )) {
      return;
    }
    try {
      await AuthService.instance.deleteAccount();
      if (context.mounted) showSnack(context, 'アカウントを削除しました');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}
