import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final storiesService = StoriesService();

class StoriesService {
  StoriesService({
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

  Future<List<Map<String, dynamic>>> listStories({
    required String idToken,
    String? artisanId,
    int limit = 50,
    int withinHours = 48,
  }) async {
    await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 200).toInt();
    final fetchSize = (safeLimit * 5).clamp(50, 400).toInt();
    final safeHours = withinHours.clamp(1, 336).toInt();
    final cutoff = DateTime.now().toUtc().subtract(Duration(hours: safeHours));

    final docs = await _firestoreClient.listDocuments(
      collectionPath: 'stories',
      idToken: idToken,
      pageSize: fetchSize,
      orderBy: 'timestamp desc',
    );

    final normalizedArtisanId = artisanId?.trim();
    final filtered = docs
        .where((doc) {
          final rawArtisanId = '${doc['artisanId'] ?? ''}';
          if (normalizedArtisanId != null &&
              normalizedArtisanId.isNotEmpty &&
              rawArtisanId != normalizedArtisanId) {
            return false;
          }

          final ts = _parseDateTime(doc['timestamp']);
          if (ts == null) return false;
          return !ts.isBefore(cutoff);
        })
        .take(safeLimit)
        .toList();

    return filtered;
  }

  Future<Map<String, dynamic>> createStory({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final mediaUrls = _readMediaUrls(payload);
    if (mediaUrls.isEmpty) {
      throw ApiException.badRequest(
        'imageUrl/mediaUrls is required and must contain at least one URL.',
      );
    }

    final content = _optionalString(payload, 'content') ??
        _optionalString(payload, 'caption') ??
        '';
    final now = DateTime.now().toUtc();
    final latitude = _optionalNum(payload, 'latitude');
    final longitude = _optionalNum(payload, 'longitude');

    final data = <String, dynamic>{
      'artisanId': uid,
      'postId': _optionalString(payload, 'postId') ?? '',
      'content': content,
      'imageUrl': mediaUrls,
      'timestamp': now.toIso8601String(),
      'expiresAt': now.add(const Duration(days: 2)).toIso8601String(),
      'isAdminPost': payload['isAdminPost'] == true,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

    return _firestoreClient.createDocument(
      collectionPath: 'stories',
      idToken: idToken,
      data: data,
    );
  }

  Future<List<Map<String, dynamic>>> listStoryVendors({
    required String idToken,
    int withinHours = 48,
    int limit = 50,
  }) async {
    await _resolveUid(idToken);
    final stories = await listStories(
      idToken: idToken,
      limit: 400,
      withinHours: withinHours,
    );

    final byVendor = <String, _VendorStoryMeta>{};
    for (final story in stories) {
      final vendorId = '${story['artisanId'] ?? ''}'.trim();
      if (vendorId.isEmpty) continue;
      final ts = _parseDateTime(story['timestamp']);
      if (ts == null) continue;

      final existing = byVendor[vendorId];
      if (existing == null) {
        byVendor[vendorId] = _VendorStoryMeta(
          latestStoryAt: ts,
          storyCount: 1,
        );
      } else {
        byVendor[vendorId] = _VendorStoryMeta(
          latestStoryAt:
              ts.isAfter(existing.latestStoryAt) ? ts : existing.latestStoryAt,
          storyCount: existing.storyCount + 1,
        );
      }
    }

    final sortedIds = byVendor.entries.toList()
      ..sort((a, b) => b.value.latestStoryAt.compareTo(a.value.latestStoryAt));

    final safeLimit = limit.clamp(1, 100).toInt();
    final result = <Map<String, dynamic>>[];
    for (final entry in sortedIds.take(safeLimit)) {
      final vendorId = entry.key;
      final profile =
          await _getVendorProfile(idToken: idToken, vendorId: vendorId);
      result.add(<String, dynamic>{
        'vendorId': vendorId,
        'latestStoryAt': entry.value.latestStoryAt.toIso8601String(),
        'storyCount': entry.value.storyCount,
        if (profile != null) 'profile': profile,
      });
    }

    return result;
  }

  Future<Map<String, dynamic>> markStoryViewed({
    required String idToken,
    required String storyId,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedStoryId = storyId.trim();
    if (normalizedStoryId.isEmpty) {
      throw ApiException.badRequest('storyId is required.');
    }

    final allViews = await _firestoreClient.listDocuments(
      collectionPath: 'storyViews',
      idToken: idToken,
      pageSize: 400,
      orderBy: 'viewedAt desc',
    );

    Map<String, dynamic>? existing;
    for (final view in allViews) {
      final isMatch = '${view['viewerId'] ?? ''}' == uid &&
          '${view['storyId'] ?? ''}' == normalizedStoryId;
      if (isMatch) {
        existing = view;
        break;
      }
    }

    if (existing != null) {
      return <String, dynamic>{
        ...existing,
        'alreadyViewed': true,
      };
    }

    final created = await _firestoreClient.createDocument(
      collectionPath: 'storyViews',
      idToken: idToken,
      data: <String, dynamic>{
        'viewerId': uid,
        'storyId': normalizedStoryId,
        'viewedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    return <String, dynamic>{
      ...created,
      'alreadyViewed': false,
    };
  }

  Future<List<String>> fetchViewedStoryIds({
    required String idToken,
    required List<String> storyIds,
  }) async {
    final uid = await _resolveUid(idToken);
    final unique = storyIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (unique.isEmpty) return <String>[];

    final views = await _firestoreClient.listDocuments(
      collectionPath: 'storyViews',
      idToken: idToken,
      pageSize: 400,
      orderBy: 'viewedAt desc',
    );

    final set = unique.toSet();
    final viewed = <String>{};
    for (final view in views) {
      if ('${view['viewerId'] ?? ''}' != uid) continue;
      final storyId = '${view['storyId'] ?? ''}';
      if (set.contains(storyId)) {
        viewed.add(storyId);
      }
    }

    return viewed.toList();
  }

  Future<Map<String, dynamic>?> _getVendorProfile({
    required String idToken,
    required String vendorId,
  }) async {
    final vendors = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: vendorId,
      idToken: idToken,
    );
    if (vendors != null) return <String, dynamic>{'id': vendorId, ...vendors};

    final artisans = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: vendorId,
      idToken: idToken,
    );
    if (artisans != null) return <String, dynamic>{'id': vendorId, ...artisans};

    return null;
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}';
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toUtc();
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

  List<String> _readMediaUrls(Map<String, dynamic> payload) {
    final source = payload['imageUrl'] ?? payload['mediaUrls'];
    if (source is! List) return <String>[];

    final urls = <String>[];
    for (final item in source) {
      if (item is String && item.trim().isNotEmpty) {
        urls.add(item.trim());
      }
    }
    return urls;
  }
}

class _VendorStoryMeta {
  const _VendorStoryMeta({
    required this.latestStoryAt,
    required this.storyCount,
  });

  final DateTime latestStoryAt;
  final int storyCount;
}
