import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final workfeedService = WorkfeedService();

class WorkfeedService {
  WorkfeedService({
    FirebaseAuthRestClient? authClient,
    FirestoreRestClient? firestoreClient,
  })  : _authClient = authClient ??
            FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
        _firestoreClient = firestoreClient ??
            FirestoreRestClient(
              projectId: AppEnv.firebaseProjectId,
              webApiKey: AppEnv.firebaseWebApiKey,
            );

  final FirebaseAuthRestClient _authClient;
  final FirestoreRestClient _firestoreClient;

  Future<List<Map<String, dynamic>>> listWorkfeeds({
    required String idToken,
    int limit = 20,
    String? artisanId,
  }) async {
    await _resolveUid(idToken);

    final safeLimit = limit.clamp(1, 100).toInt();
    final items = await _firestoreClient.listDocuments(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: safeLimit,
      orderBy: 'timestamp desc',
    );

    if (artisanId == null || artisanId.trim().isEmpty) {
      return items;
    }

    final normalized = artisanId.trim();
    return items
        .where((item) => '${item['artisanId'] ?? ''}' == normalized)
        .toList();
  }

  Future<Map<String, dynamic>> getWorkfeed({
    required String idToken,
    required String postId,
  }) async {
    await _resolveUid(idToken);
    if (postId.trim().isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final doc = await _firestoreClient.getDocument(
      collectionPath: 'posts',
      documentId: postId.trim(),
      idToken: idToken,
    );
    if (doc == null) {
      throw ApiException.notFound('Workfeed post not found.');
    }

    return <String, dynamic>{
      'id': postId.trim(),
      ...doc,
    };
  }

  Future<Map<String, dynamic>> createWorkfeed({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final media = _readMediaUrls(payload);
    final content = _optionalString(payload, 'content') ??
        _optionalString(payload, 'caption') ??
        '';

    if (content.isEmpty && media.isEmpty) {
      throw ApiException.badRequest(
        'Provide at least one of content/caption or imageUrl/mediaUrls.',
      );
    }

    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final latitude = _optionalNum(payload, 'latitude');
    final longitude = _optionalNum(payload, 'longitude');
    final isAdminPost = payload['isAdminPost'] == true;

    final postData = <String, dynamic>{
      'artisanId': uid,
      'content': content,
      'imageUrl': media,
      'timestamp': nowIso,
      'likes': <dynamic>[],
      'isAdminPost': isAdminPost,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      ..._additionalPostFields(payload),
    };

    final post = await _firestoreClient.createDocument(
      collectionPath: 'posts',
      idToken: idToken,
      data: postData,
    );

    Map<String, dynamic>? story;
    final mirrorToStories = payload['mirrorToStories'] != false;
    if (mirrorToStories) {
      story = await _firestoreClient.createDocument(
        collectionPath: 'stories',
        idToken: idToken,
        data: <String, dynamic>{
          'artisanId': uid,
          'postId': post['id'],
          'content': content,
          'imageUrl': media,
          'timestamp': nowIso,
          'expiresAt': now.add(const Duration(days: 2)).toIso8601String(),
          'isAdminPost': isAdminPost,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        },
      );
    }

    return <String, dynamic>{
      'post': post,
      if (story != null) 'story': story,
    };
  }

  Future<Map<String, dynamic>> deleteWorkfeed({
    required String idToken,
    required String postId,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final existing = await _firestoreClient.getDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
    );
    if (existing == null) {
      throw ApiException.notFound('Workfeed post not found.');
    }

    if ('${existing['artisanId'] ?? ''}' != uid) {
      throw ApiException.forbidden('You can only delete your own posts.');
    }

    await _firestoreClient.deleteDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
    );

    return <String, dynamic>{
      'deleted': true,
      'postId': normalizedPostId,
    };
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}';
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  List<String> _readMediaUrls(Map<String, dynamic> payload) {
    final primary = payload['imageUrl'];
    final fallback = payload['mediaUrls'];
    final source = primary ?? fallback;
    if (source is! List) return <String>[];

    final result = <String>[];
    for (final item in source) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(item.trim());
      }
    }
    return result;
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  num? _optionalNum(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is num) return value;
    if (value is String && value.trim().isNotEmpty) {
      return num.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic> _additionalPostFields(Map<String, dynamic> payload) {
    const blocked = <String>{
      'artisanId',
      'content',
      'caption',
      'imageUrl',
      'mediaUrls',
      'timestamp',
      'likes',
      'isAdminPost',
      'latitude',
      'longitude',
      'mirrorToStories',
    };

    final result = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }
}
