import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/utils/geo.dart';

final workfeedService = WorkfeedService();

class WorkfeedService {
  WorkfeedService({
    FirebaseAuthRestClient? authClient,
    FirestoreRestClient? firestoreClient,
  }) : _authClient =
           authClient ??
           FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
       _firestoreClient =
           firestoreClient ??
           FirestoreRestClient(
             projectId: AppEnv.firebaseProjectId,
             webApiKey: AppEnv.firebaseWebApiKey,
           );

  final FirebaseAuthRestClient _authClient;
  final FirestoreRestClient _firestoreClient;

  Future<({List<Map<String, dynamic>> items, String? nextPageToken})> listWorkfeeds({
    required String idToken,
    int limit = 20,
    String? artisanId,
    bool followingOnly = false,
    String? pageToken,
    double? latitude,
    double? longitude,
  }) async {
    final uid = await _resolveUid(idToken);

    final safeLimit = limit.clamp(1, 100);
    final followedIds = followingOnly
        ? await _readFollowingIds(idToken: idToken, uid: uid)
        : const <String>{};

    if (followingOnly && followedIds.isEmpty) {
      return (items: <Map<String, dynamic>>[], nextPageToken: null);
    }

    final fetchLimit = followingOnly ? 100 : safeLimit;
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: fetchLimit,
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );

    final normalizedArtisanId = artisanId?.trim();
    final hasLocationFilter = latitude != null && longitude != null;
    final filtered = page.documents.where((item) {
      final postArtisanId = '${item['artisanId'] ?? ''}'.trim();

      if (normalizedArtisanId != null &&
          normalizedArtisanId.isNotEmpty &&
          postArtisanId != normalizedArtisanId) {
        return false;
      }

      if (followingOnly && !followedIds.contains(postArtisanId)) {
        return false;
      }

      if (hasLocationFilter) {
        final itemLat = _readDouble(item['latitude']);
        final itemLon = _readDouble(item['longitude']);
        if (itemLat == null || itemLon == null) return false;
        final km = distanceKm(
          lat1: latitude!,
          lon1: longitude!,
          lat2: itemLat,
          lon2: itemLon,
        );
        if (km > 10) return false;
      }

      return true;
    }).toList();

    final trimmed = filtered.length <= safeLimit
        ? filtered
        : filtered.sublist(0, safeLimit);

    final enriched = await _enrichWithVerification(
      posts: trimmed,
      idToken: idToken,
      uid: uid,
    );

    return (items: enriched, nextPageToken: page.nextPageToken);
  }

  Future<List<Map<String, dynamic>>> _enrichWithVerification({
    required List<Map<String, dynamic>> posts,
    required String idToken,
    required String uid,
  }) async {
    final uniqueIds = posts
        .map((p) => '${p['artisanId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final profileMap = <String, Map<String, dynamic>>{};
    for (final artisanUid in uniqueIds) {
      for (final collection in const <String>['artisans', 'vendors']) {
        final doc = await _firestoreClient.getDocument(
          collectionPath: collection,
          documentId: artisanUid,
          idToken: idToken,
        );
        if (doc != null) {
          profileMap[artisanUid] = doc;
          break;
        }
      }
    }

    final savedPostDocs = await _firestoreClient.listDocuments(
      collectionPath: 'userSavedPosts/$uid/posts',
      idToken: idToken,
    );
    final savedPostIds = savedPostDocs.map((d) => '${d['id'] ?? ''}').toSet();

    return posts.map((post) {
      final artisanUid = '${post['artisanId'] ?? ''}'.trim();
      final profile = profileMap[artisanUid] ?? const <String, dynamic>{};
      final postId = '${post['id'] ?? ''}';
      
      final likes = _readStringList(post['likes']);

      return <String, dynamic>{
        ...post,
        'isVerified': profile['isVerified'] == true,
        'isSaved': savedPostIds.contains(postId),
        'isLiked': likes.contains(uid),
        'artisanName': post['artisanName'] ??
            profile['name'] ??
            profile['username'] ??
            profile['displayName'] ??
            '',
        'artisanUsername': post['artisanUsername'] ??
            profile['username'] ??
            profile['name'] ??
            '',
        'artisanImage': post['artisanImage'] ??
            post['profileImage'] ??
            profile['profileImageUrl'] ??
            profile['imageUrl'] ??
            profile['profileImage'] ??
            '',
        'artisanTitle': post['artisanTitle'] ??
            profile['title'] ??
            profile['artisanTitle'] ??
            '',
        'artisanRating': profile['rating'] ?? 0.0,
      };
    }).toList();
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
    final content =
        _optionalString(payload, 'content') ??
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
    final thumbnailUrl = _optionalString(payload, 'thumbnailUrl') ?? '';

    final postData = <String, dynamic>{
      'artisanId': uid,
      'content': content,
      'imageUrl': media,
      'timestamp': nowIso,
      'likes': <dynamic>[],
      'isAdminPost': isAdminPost,
      if (thumbnailUrl.isNotEmpty) 'thumbnailUrl': thumbnailUrl,
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
          if (thumbnailUrl.isNotEmpty) 'thumbnailUrl': thumbnailUrl,
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

  Future<Set<String>> _readFollowingIds({
    required String idToken,
    required String uid,
  }) async {
    final followed = <String>{};
    for (final collection in const <String>[
      'customers',
      'vendors',
      'artisans',
    ]) {
      final profile = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
      );
      if (profile == null) continue;
      followed.addAll(_readStringList(profile['followingIds']));
    }
    return followed;
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
      'thumbnailUrl',
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}
