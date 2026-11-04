import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/config.dart';
import '../models/models.dart';

/// サーバーのエラー（doc/design.md 7.4）
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.extra = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> extra;

  int? get nextFreeAt => extra['nextFreeAt'] as int?;

  @override
  String toString() => message;
}

class UploadImage {
  UploadImage(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

/// TechMeku サーバー API
class Api {
  Api._();
  static final Api instance = Api._();

  final _client = http.Client();

  /// セッショントークン（AuthService が設定する）
  String? token;

  /// 401 を受けたときに呼ぶ（ログアウト処理）
  void Function()? onUnauthorized;

  Uri _u(String path) => Uri.parse('${AppConfig.apiBase}$path');
  String imageUrl(String key) => '${AppConfig.apiBase}/images/$key';

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(String method, String path, {Object? json}) async {
    final req = http.Request(method, _u(path))..headers.addAll(_headers);
    if (json != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(json);
    }
    return _handle(await _client.send(req));
  }

  Future<Map<String, dynamic>> _handle(http.StreamedResponse res) async {
    final text = utf8.decode(await res.stream.toBytes());
    Map<String, dynamic> body;
    try {
      body = text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (res.statusCode >= 400) {
      final e = body['error'] as Map<String, dynamic>? ?? {};
      final ex = ApiException(res.statusCode, e['code'] as String? ?? 'ERROR', e['message'] as String? ?? '通信に失敗しました（${res.statusCode}）', e);
      if (res.statusCode == 401 && token != null) onUnauthorized?.call();
      throw ex;
    }
    return body;
  }

  Future<Map<String, dynamic>> _guard(Future<Map<String, dynamic>> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 30));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'NETWORK', '通信に失敗しました。接続を確認してください');
    }
  }

  // ---- 認証
  Future<(String, String)> loginWithGoogle(String idToken) async {
    final r = await _guard(() => _send('POST', '/auth/google', json: {'idToken': idToken}));
    return (r['token'] as String, (r['user'] as Map)['nickname'] as String);
  }

  Future<Map<String, dynamic>> me() => _guard(() => _send('GET', '/me'));
  Future<void> updateNickname(String n) => _guard(() => _send('PATCH', '/me', json: {'nickname': n}));
  Future<void> deleteAccount() => _guard(() => _send('DELETE', '/me'));

  // ---- 投稿
  Future<Map<String, dynamic>> status() => _guard(() => _send('GET', '/status'));

  Future<List<Post>> posts() async {
    final r = await _guard(() => _send('GET', '/posts'));
    return (r['posts'] as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<Post>> myPosts() async {
    final r = await _guard(() => _send('GET', '/posts/mine'));
    return (r['posts'] as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Post> post(String id) async => Post.fromJson((await _guard(() => _send('GET', '/posts/$id')))['post'] as Map<String, dynamic>);

  Future<Post> savePost({
    String? id,
    required String title,
    required String body,
    required List<String> tags,
    List<String> keepImages = const [],
    List<UploadImage> images = const [],
  }) async {
    final req = http.MultipartRequest(id == null ? 'POST' : 'PATCH', _u(id == null ? '/posts' : '/posts/$id'))..headers.addAll(_headers);
    req.fields['data'] = jsonEncode({'title': title, 'body': body, 'tags': tags, 'keepImages': keepImages});
    for (var i = 0; i < images.length; i++) {
      final ext = images[i].mime == 'image/webp' ? 'webp' : 'jpg';
      req.files.add(http.MultipartFile.fromBytes('images', images[i].bytes, filename: '$i.$ext', contentType: MediaType.parse(images[i].mime)));
    }
    final r = await _guard(() async => _handle(await _client.send(req)));
    return Post.fromJson(r['post'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String id) => _guard(() => _send('DELETE', '/posts/$id'));

  Future<Map<String, dynamic>> like(String id, bool on) => _guard(() => _send(on ? 'POST' : 'DELETE', '/posts/$id/like'));

  Future<(List<Comment>, int)> comments(String postId) async {
    final r = await _guard(() => _send('GET', '/posts/$postId/comments'));
    return ((r['comments'] as List).map((j) => Comment.fromJson(j as Map<String, dynamic>)).toList(), r['commentCount'] as int? ?? 0);
  }

  Future<Map<String, dynamic>> addComment(String postId, String body) => _guard(() => _send('POST', '/posts/$postId/comments', json: {'body': body}));
  Future<void> deleteComment(String id) => _guard(() => _send('DELETE', '/comments/$id'));

  Future<void> report(String targetType, String targetId, String reason) =>
      _guard(() => _send('POST', '/reports', json: {'targetType': targetType, 'targetId': targetId, 'reason': reason}));
}
