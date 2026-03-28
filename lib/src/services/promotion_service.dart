import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';

final promotionService = PromotionService();

class PromotionService {
  PromotionService({
    FirebaseAuthRestClient? authClient,
    FirestoreRestClient? firestoreClient,
    MediaUploadService? mediaService,
  })  : _authClient = authClient ??
            FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
        _firestoreClient = firestoreClient ??
            FirestoreRestClient(
              projectId: AppEnv.firebaseProjectId,
              webApiKey: AppEnv.firebaseWebApiKey,
            ),
        _mediaService = mediaService ?? mediaUploadService;

  final FirebaseAuthRestClient _authClient;
  final FirestoreRestClient _firestoreClient;
  final MediaUploadService _mediaService;
  final Random _random = Random();

  Future<Map<String, dynamic>> createPromotedPost({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final transactionId = _requiredString(payload, 'transactionId');
    final paymentType = _optionalString(payload, 'paymentType') ?? 'Ads';
    final txLookup = await _findPromotionTransaction(
      idToken: idToken,
      uid: uid,
      paymentTypeHint: paymentType,
      transactionId: transactionId,
    );
    final txPath = txLookup.collectionPath;
    final transaction = txLookup.document;
    if (transaction == null) {
      throw ApiException.notFound('Payment transaction not found.');
    }
    if (transaction['isConfirmed'] != true) {
      throw ApiException.forbidden('Payment is not confirmed yet.');
    }
    if (transaction['processed'] == true) {
      throw ApiException.conflict(
          'Payment has already been used for promotion.');
    }

    final packageData = _mapOrNull(payload['packageData']) ??
        _mapOrNull(transaction['packageData']) ??
        <String, dynamic>{};

    var mediaUrl = _optionalString(payload, 'imageUrl') ??
        _optionalString(payload, 'mediaUrl') ??
        '';
    final mediaBase64 = _optionalString(payload, 'mediaBase64');
    if (mediaBase64 != null && mediaBase64.isNotEmpty) {
      final uploaded = await _mediaService.uploadForPath(
        idToken: idToken,
        mediaBase64: mediaBase64,
        folder: 'promoted_posts',
        defaultNamePrefix: 'promoted_${DateTime.now().millisecondsSinceEpoch}',
        contentType: _optionalString(payload, 'contentType'),
        fileName: _optionalString(payload, 'fileName'),
      );
      mediaUrl = '${uploaded['downloadUrl'] ?? ''}';
    }
    if (mediaUrl.trim().isEmpty) {
      throw ApiException.badRequest(
          'imageUrl/mediaUrl or mediaBase64 is required.');
    }

    final profile = await _resolveActorProfile(idToken: idToken, uid: uid);
    final postId = _optionalString(payload, 'postId') ?? _nextId('post');
    final now = DateTime.now().toUtc();
    final dueDate =
        now.add(Duration(days: _resolveDurationDays(packageData) ?? 7));

    final post = <String, dynamic>{
      'id': postId,
      'artisanId': uid,
      'artisanUsername': profile.name,
      'caption': _optionalString(payload, 'caption') ??
          _optionalString(payload, 'content') ??
          '',
      'content': _optionalString(payload, 'content') ??
          _optionalString(payload, 'caption') ??
          '',
      'imageUrl': mediaUrl,
      'type': 'promotedPost',
      'isArtisan': profile.isVendor,
      'timestamp': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'views': _asInt(payload['views']) ?? 0,
      'taps': _asInt(payload['taps']) ?? 0,
      'dueDate': dueDate.toIso8601String(),
      'transactionId': transactionId,
      'packageData': packageData,
      'packageName': packageData['packageName'] ?? '',
    };

    await _firestoreClient.setDocument(
      collectionPath: 'posts',
      documentId: postId,
      idToken: idToken,
      data: post,
    );

    await _firestoreClient.setDocument(
      collectionPath: txPath,
      documentId: transactionId,
      idToken: idToken,
      data: <String, dynamic>{
        ...transaction,
        'processed': true,
        'processedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
    );

    return <String, dynamic>{
      'post': post,
      'transaction': <String, dynamic>{
        'id': transactionId,
        'paymentType': txLookup.paymentType,
        'processed': true,
      },
    };
  }

  Future<Map<String, dynamic>> listPromotedPosts({
    required String idToken,
    String? artisanId,
    bool activeOnly = true,
    int limit = 30,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'posts',
      idToken: idToken,
      pageSize: limit.clamp(1, 200).toInt() * 3,
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    final now = DateTime.now().toUtc();
    final filtered = <Map<String, dynamic>>[];
    for (final doc in page.documents) {
      if ('${doc['type'] ?? ''}' != 'promotedPost') continue;
      if (artisanId != null &&
          artisanId.trim().isNotEmpty &&
          '${doc['artisanId'] ?? ''}'.trim() != artisanId.trim()) {
        continue;
      }
      if (activeOnly) {
        final due = DateTime.tryParse('${doc['dueDate'] ?? ''}');
        if (due != null && !due.isAfter(now)) continue;
      }
      filtered.add(doc);
      if (filtered.length >= limit.clamp(1, 200).toInt()) break;
    }
    return <String, dynamic>{
      'items': filtered,
      'count': filtered.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createAdAnalyticsEvent({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final now = _nowIso();

    final postId = _optionalString(payload, 'postId') ?? '';
    final artisanId = _optionalString(payload, 'artisanId') ?? '';
    final eventType = _optionalString(payload, 'eventType') ??
        _fromTapType(_optionalString(payload, 'tapType'));
    final tapType = _optionalString(payload, 'tapType') ?? '';
    final userType = _optionalString(payload, 'userType') ?? 'customer';
    final query = _optionalString(payload, 'query') ?? '';
    final source = _optionalString(payload, 'source') ?? 'workfeeds';

    final analyticsId = _optionalString(payload, 'id') ?? _nextId('ad');
    final adAnalytics = <String, dynamic>{
      'id': analyticsId,
      'userId': uid,
      'tapType': tapType,
      'eventType': eventType,
      'postId': postId,
      'artisanId': artisanId,
      'userType': userType,
      'source': source,
      'query': query,
      'timestamp': now,
      'createdAt': now,
    };
    await _firestoreClient.setDocument(
      collectionPath: 'ad_analytics',
      documentId: analyticsId,
      idToken: idToken,
      data: adAnalytics,
    );

    if (eventType != null && eventType.isNotEmpty && artisanId.isNotEmpty) {
      final viewer = await _resolveActorProfile(idToken: idToken, uid: uid);
      final eventId = _nextId('evt');
      final event = <String, dynamic>{
        'id': eventId,
        'eventType': eventType,
        'artisanId': artisanId,
        'postId': postId,
        'isPromoted': true,
        'tapType': tapType,
        'viewerId': uid,
        'viewerName': viewer.name,
        'viewerImage': viewer.profileImage,
        'viewerType': viewer.type,
        'source': source,
        'query': query,
        'queryLower': query.trim().toLowerCase(),
        'timestamp': now,
        'createdAt': now,
      };
      await _firestoreClient.setDocument(
        collectionPath: 'artisan_analytics_events',
        documentId: eventId,
        idToken: idToken,
        data: event,
      );
    }

    if (postId.isNotEmpty) {
      final post = await _firestoreClient.getDocument(
        collectionPath: 'posts',
        documentId: postId,
        idToken: idToken,
      );
      if (post != null && '${post['type'] ?? ''}' == 'promotedPost') {
        final updates = <String, dynamic>{...post};
        if (eventType == 'post_impression') {
          updates['views'] = (_asInt(post['views']) ?? 0) + 1;
        } else if (eventType == 'post_tap') {
          updates['taps'] = (_asInt(post['taps']) ?? 0) + 1;
        }
        updates['updatedAt'] = now;
        await _firestoreClient.setDocument(
          collectionPath: 'posts',
          documentId: postId,
          idToken: idToken,
          data: updates,
        );
      }
    }

    return adAnalytics;
  }

  Future<Map<String, dynamic>> listAdAnalytics({
    required String idToken,
    String? artisanId,
    String? postId,
    int days = 30,
    int limit = 100,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'ad_analytics',
      idToken: idToken,
      pageSize: limit.clamp(1, 400).toInt() * 3,
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    final cutoff =
        DateTime.now().toUtc().subtract(Duration(days: days.clamp(1, 365)));
    final items = <Map<String, dynamic>>[];
    var impressions = 0;
    var taps = 0;
    var searches = 0;
    for (final item in page.documents) {
      if (artisanId != null &&
          artisanId.trim().isNotEmpty &&
          '${item['artisanId'] ?? ''}'.trim() != artisanId.trim()) {
        continue;
      }
      if (postId != null &&
          postId.trim().isNotEmpty &&
          '${item['postId'] ?? ''}'.trim() != postId.trim()) {
        continue;
      }
      final at = DateTime.tryParse('${item['timestamp'] ?? ''}');
      if (at != null && at.isBefore(cutoff)) continue;
      items.add(item);
      final ev = '${item['eventType'] ?? ''}'.trim().toLowerCase();
      if (ev == 'post_impression') impressions++;
      if (ev == 'post_tap') taps++;
      if (ev == 'search') searches++;
      if (items.length >= limit.clamp(1, 400).toInt()) break;
    }
    return <String, dynamic>{
      'items': items,
      'count': items.length,
      'summary': <String, dynamic>{
        'impressions': impressions,
        'taps': taps,
        'searches': searches,
      },
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

  Future<_TransactionLookup> _findPromotionTransaction({
    required String idToken,
    required String uid,
    required String paymentTypeHint,
    required String transactionId,
  }) async {
    final types = <String>{
      paymentTypeHint.trim(),
      'Ads',
      'ads',
      'ADs',
      'premium',
      'Premium',
    }.where((t) => t.isNotEmpty);

    for (final t in types) {
      final path = 'transactionswp/$uid/$t';
      final tx = await _firestoreClient.getDocument(
        collectionPath: path,
        documentId: transactionId,
        idToken: idToken,
      );
      if (tx != null) {
        return _TransactionLookup(
            collectionPath: path, paymentType: t, document: tx);
      }
    }
    return _TransactionLookup(
        collectionPath: 'transactionswp/$uid/$paymentTypeHint',
        paymentType: paymentTypeHint,
        document: null);
  }

  Future<_ActorProfile> _resolveActorProfile({
    required String idToken,
    required String uid,
  }) async {
    final vendor = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: uid,
      idToken: idToken,
    );
    if (vendor != null) {
      return _ActorProfile(
        uid: uid,
        type: 'vendor',
        name: _optionalText(vendor['name']) ??
            _optionalText(vendor['username']) ??
            'Vendor',
        profileImage: _optionalText(vendor['profileImage']) ??
            _optionalText(vendor['imageUrl']) ??
            '',
        isVendor: true,
      );
    }

    final artisan = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: uid,
      idToken: idToken,
    );
    if (artisan != null) {
      return _ActorProfile(
        uid: uid,
        type: 'artisan',
        name: _optionalText(artisan['name']) ??
            _optionalText(artisan['username']) ??
            'Artisan',
        profileImage: _optionalText(artisan['profileImage']) ??
            _optionalText(artisan['imageUrl']) ??
            '',
        isVendor: true,
      );
    }

    final customer = await _firestoreClient.getDocument(
      collectionPath: 'customers',
      documentId: uid,
      idToken: idToken,
    );
    if (customer != null) {
      return _ActorProfile(
        uid: uid,
        type: 'customer',
        name: _optionalText(customer['username']) ??
            _optionalText(customer['name']) ??
            'Customer',
        profileImage: _optionalText(customer['profileImage']) ??
            _optionalText(customer['imageUrl']) ??
            '',
        isVendor: false,
      );
    }

    final legacy = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
    );
    if (legacy != null) {
      return _ActorProfile(
        uid: uid,
        type: 'user',
        name: _optionalText(legacy['name']) ??
            _optionalText(legacy['username']) ??
            'User',
        profileImage: _optionalText(legacy['profileImage']) ??
            _optionalText(legacy['imageUrl']) ??
            '',
        isVendor: false,
      );
    }

    return _ActorProfile(
      uid: uid,
      type: 'unknown',
      name: 'WorkPal User',
      profileImage: '',
      isVendor: false,
    );
  }

  String? _fromTapType(String? tapType) {
    final t = (tapType ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains('view') || t.contains('impression'))
      return 'post_impression';
    if (t.contains('search')) return 'search';
    return 'post_tap';
  }

  int? _resolveDurationDays(Map<String, dynamic> packageData) {
    final raw = '${packageData['duration'] ?? ''}'.trim().toLowerCase();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw.split(' ').first);
    if (n == null || n < 1) return null;
    if (raw.contains('month')) return n * 30;
    if (raw.contains('week')) return n * 7;
    return n;
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty)
      return int.tryParse(value.trim());
    return null;
  }

  String _requiredString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw ApiException.badRequest('$key is required.');
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  String? _optionalText(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  String _nextId(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}

class _ActorProfile {
  const _ActorProfile({
    required this.uid,
    required this.type,
    required this.name,
    required this.profileImage,
    required this.isVendor,
  });

  final String uid;
  final String type;
  final String name;
  final String profileImage;
  final bool isVendor;
}

class _TransactionLookup {
  const _TransactionLookup({
    required this.collectionPath,
    required this.paymentType,
    required this.document,
  });

  final String collectionPath;
  final String paymentType;
  final Map<String, dynamic>? document;
}
