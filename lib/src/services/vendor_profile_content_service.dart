import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final vendorProfileContentService = VendorProfileContentService();

class VendorProfileContentService {
  VendorProfileContentService({
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

  Future<Map<String, dynamic>> getFullVendorProfile({
    required String idToken,
    required String vendorId,
  }) async {
    await _resolveUid(idToken);
    final normalizedId = _requiredVendorId(vendorId);

    // Fetch profile from vendors then artisans.
    Map<String, dynamic> profile = {};
    for (final collection in const <String>['vendors', 'artisans']) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: normalizedId,
        idToken: idToken,
      );
      if (doc != null) {
        profile = <String, dynamic>{...doc, ...profile};
        break;
      }
    }
    // Also merge users doc for any extra fields.
    final usersDoc = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: normalizedId,
      idToken: idToken,
    );
    if (usersDoc != null) {
      profile = <String, dynamic>{...usersDoc, ...profile};
    }

    // Posts.
    final postsPage = await _firestoreClient.listDocumentsPage(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: 20,
      orderBy: 'timestamp desc',
    );
    final posts = postsPage.documents
        .where((d) => '${d['artisanId'] ?? ''}'.trim() == normalizedId)
        .take(20)
        .toList();

    // Reviews.
    String? reviewCollection;
    for (final c in const <String>['vendors', 'artisans']) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: c,
        documentId: normalizedId,
        idToken: idToken,
      );
      if (doc != null) { reviewCollection = c; break; }
    }
    List<Map<String, dynamic>> reviews = [];
    if (reviewCollection != null) {
      final reviewsPage = await _firestoreClient.listDocumentsPage(
        collectionPath: '$reviewCollection/$normalizedId/reviews',
        idToken: idToken,
        pageSize: 20,
        orderBy: 'createdAt desc',
      );
      reviews = reviewsPage.documents;
    }

    // Portfolio.
    final portfolioResult = await listVendorPortfolio(
      idToken: idToken,
      vendorId: normalizedId,
      limit: 20,
    );

    // Jobs.
    final jobsPage = await _firestoreClient.listDocumentsPage(
      collectionPath: 'job_posts',
      idToken: idToken,
      pageSize: 20,
      orderBy: 'createdAt desc',
    );
    final jobs = jobsPage.documents
        .where((d) =>
            '${d['artisanId'] ?? d['vendorId'] ?? ''}'.trim() == normalizedId)
        .take(20)
        .toList();

    // Followers count.
    final followersPage = await _firestoreClient.listDocumentsPage(
      collectionPath: 'vendors/$normalizedId/followers',
      idToken: idToken,
      pageSize: 100,
    );
    final followersCount = followersPage.documents.length;

    return <String, dynamic>{
      'profile': <String, dynamic>{
        ...profile,
        'vendorId': normalizedId,
        'rating': _asDouble(profile['rating']) ?? 0.0,
        'ratingQuality': _asDouble(profile['ratingQuality']) ?? 0.0,
        'ratingComm': _asDouble(profile['ratingComm']) ?? 0.0,
        'ratingTimeliness': _asDouble(profile['ratingTimeliness']) ?? 0.0,
        'ratingValue': _asDouble(profile['ratingValue']) ?? 0.0,
        'reviewCount': _asInt(profile['reviewCount']) ?? reviews.length,
        'followersCount': followersCount,
        'isVerified': profile['isVerified'] == true,
      },
      'posts': posts,
      'portfolio': portfolioResult['items'] ?? [],
      'reviews': reviews,
      'jobs': jobs,
    };
  }

  Future<Map<String, dynamic>> listVendorWorkfeeds({
    required String idToken,
    required String vendorId,
    int limit = 20,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final normalizedVendorId = _requiredVendorId(vendorId);
    final safeLimit = limit.clamp(1, 100).toInt();

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: max(safeLimit * 4, 80).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );

    final items = page.documents
        .where(
            (doc) => '${doc['artisanId'] ?? ''}'.trim() == normalizedVendorId)
        .take(safeLimit)
        .toList();

    return <String, dynamic>{
      'vendorId': normalizedVendorId,
      'items': items,
      'count': items.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> listVendorPortfolio({
    required String idToken,
    required String vendorId,
    int limit = 100,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final normalizedVendorId = _requiredVendorId(vendorId);
    final safeLimit = limit.clamp(1, 400).toInt();

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: max(safeLimit * 3, 120).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );

    final mediaItems = <Map<String, dynamic>>[];
    for (final post in page.documents) {
      if ('${post['artisanId'] ?? ''}'.trim() != normalizedVendorId) continue;

      final postId = '${post['id'] ?? ''}';
      final timestamp = '${post['timestamp'] ?? ''}';
      final caption = '${post['content'] ?? ''}';

      for (final url in _extractImageUrls(post['imageUrl'])) {
        mediaItems.add(<String, dynamic>{
          'postId': postId,
          'url': url,
          'timestamp': timestamp,
          'caption': caption,
        });
        if (mediaItems.length >= safeLimit) break;
      }
      if (mediaItems.length >= safeLimit) break;
    }

    return <String, dynamic>{
      'vendorId': normalizedVendorId,
      'items': mediaItems,
      'mediaUrls': mediaItems.map((e) => '${e['url']}').toList(),
      'count': mediaItems.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> listVendorReviews({
    required String idToken,
    required String vendorId,
    int limit = 10,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final normalizedVendorId = _requiredVendorId(vendorId);
    final safeLimit = limit.clamp(1, 100).toInt();

    final vendorDoc = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: normalizedVendorId,
      idToken: idToken,
    );
    final artisanDoc = vendorDoc == null
        ? await _firestoreClient.getDocument(
            collectionPath: 'artisans',
            documentId: normalizedVendorId,
            idToken: idToken,
          )
        : null;
    final profile = vendorDoc ?? artisanDoc ?? <String, dynamic>{};

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'vendors/$normalizedVendorId/reviews',
      idToken: idToken,
      pageSize: safeLimit,
      orderBy: 'createdAt desc',
      pageToken: pageToken,
    );

    return <String, dynamic>{
      'vendorId': normalizedVendorId,
      'summary': <String, dynamic>{
        'rating': _asDouble(profile['rating']) ?? 0.0,
        'reviewCount': _asInt(profile['reviewCount']) ?? page.documents.length,
        'ratingQuality': _asDouble(profile['ratingQuality']) ?? 0.0,
        'ratingComm': _asDouble(profile['ratingComm']) ?? 0.0,
        'ratingTimeliness': _asDouble(profile['ratingTimeliness']) ?? 0.0,
        'ratingValue': _asDouble(profile['ratingValue']) ?? 0.0,
      },
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  String _requiredVendorId(String vendorId) {
    final normalized = vendorId.trim();
    if (normalized.isEmpty) {
      throw ApiException.badRequest('vendor_id is required.');
    }
    return normalized;
  }

  List<String> _extractImageUrls(dynamic raw) {
    final urls = <String>[];
    if (raw is String && raw.trim().isNotEmpty) {
      if (!_looksLikeVideo(raw)) urls.add(raw.trim());
      return urls;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is! String || item.trim().isEmpty) continue;
        if (_looksLikeVideo(item)) continue;
        urls.add(item.trim());
      }
    }
    return urls;
  }

  bool _looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm');
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}
