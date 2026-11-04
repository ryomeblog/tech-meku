import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 端末側 DB（doc/design.md 6.2）
class AppDb {
  AppDb._();
  static Database? _db;

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'techmeku.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      final b = db.batch();
      b.execute('''
        CREATE TABLE stock_articles (
          id              TEXT PRIMARY KEY,
          source          TEXT NOT NULL,
          source_key      TEXT NOT NULL,
          url             TEXT,
          origin          TEXT NOT NULL,
          batch_run_id    TEXT,
          title           TEXT NOT NULL,
          author          TEXT,
          tags_json       TEXT,
          summary         TEXT,
          thumbnail_path  TEXT,
          dir_path        TEXT NOT NULL,
          size_bytes      INTEGER NOT NULL,
          likes_at_fetch  INTEGER,
          is_paid_partial INTEGER DEFAULT 0,
          published_at    INTEGER,
          downloaded_at   INTEGER NOT NULL,
          viewed_at       INTEGER,
          read_at         INTEGER,
          pending_evict   INTEGER DEFAULT 0,
          app_expires_at  INTEGER,
          UNIQUE (source, source_key)
        )''');
      b.execute('''
        CREATE TABLE cache_entries (
          id          TEXT PRIMARY KEY,
          source      TEXT NOT NULL,
          source_key  TEXT NOT NULL,
          url         TEXT NOT NULL,
          title       TEXT NOT NULL,
          cached_at   INTEGER NOT NULL,
          expires_at  INTEGER NOT NULL,
          UNIQUE (source, source_key)
        )''');
      b.execute('''
        CREATE TABLE liked_items (
          id          TEXT PRIMARY KEY,
          kind        TEXT NOT NULL,
          source      TEXT NOT NULL,
          source_key  TEXT NOT NULL,
          url         TEXT,
          title       TEXT NOT NULL,
          liked_at    INTEGER NOT NULL,
          UNIQUE (source, source_key)
        )''');
      b.execute('''
        CREATE TABLE batch_runs (
          id            TEXT PRIMARY KEY,
          trigger       TEXT NOT NULL,
          tags_json     TEXT NOT NULL,
          started_at    INTEGER NOT NULL,
          finished_at   INTEGER,
          status        TEXT NOT NULL,
          new_count     INTEGER DEFAULT 0,
          kept_count    INTEGER DEFAULT 0,
          cached_count  INTEGER DEFAULT 0,
          deleted_count INTEGER DEFAULT 0,
          errors_json   TEXT
        )''');
      b.execute('CREATE INDEX idx_stock_order ON stock_articles(viewed_at, read_at, downloaded_at)');
      await b.commit(noResult: true);
    });
    return _db!;
  }
}
