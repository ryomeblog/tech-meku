-- TechMeku D1 schema (doc/design.md 7.2)
CREATE TABLE users (
  id          TEXT PRIMARY KEY,
  sub_hash    TEXT NOT NULL UNIQUE,
  nickname    TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE bans (
  sub_hash    TEXT PRIMARY KEY,
  reason      TEXT,
  created_at  INTEGER NOT NULL
);

CREATE TABLE posts (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  title         TEXT NOT NULL,
  body_md       TEXT NOT NULL,
  tags_json     TEXT NOT NULL,
  images_json   TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  edited        INTEGER NOT NULL DEFAULT 0,
  expires_at    INTEGER NOT NULL,
  like_count    INTEGER NOT NULL DEFAULT 0,
  comment_count INTEGER NOT NULL DEFAULT 0,
  report_count  INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'active'
);
CREATE INDEX idx_posts_expires ON posts(expires_at);
CREATE INDEX idx_posts_user ON posts(user_id, expires_at);
CREATE INDEX idx_posts_created ON posts(created_at);

CREATE TABLE likes (
  post_id     TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  active      INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX idx_likes_user ON likes(user_id);

CREATE TABLE comments (
  id            TEXT PRIMARY KEY,
  post_id       TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  body          TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  report_count  INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'active'
);
CREATE INDEX idx_comments_post ON comments(post_id, created_at);
CREATE INDEX idx_comments_user ON comments(user_id);

CREATE TABLE comment_extends (
  post_id  TEXT NOT NULL,
  user_id  TEXT NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE reports (
  id           TEXT PRIMARY KEY,
  target_type  TEXT NOT NULL,
  target_id    TEXT NOT NULL,
  post_id      TEXT NOT NULL,
  reporter_id  TEXT NOT NULL,
  reason       TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  UNIQUE (target_type, target_id, reporter_id)
);
CREATE INDEX idx_reports_reporter ON reports(reporter_id);
CREATE INDEX idx_reports_post ON reports(post_id);

CREATE TABLE signup_ip_counts (
  ip_hash  TEXT NOT NULL,
  day      TEXT NOT NULL,
  count    INTEGER NOT NULL,
  PRIMARY KEY (ip_hash, day)
);
