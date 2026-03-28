import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final reviewService = ReviewService();

class ReviewService {
  ReviewService({
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
  final Random _random = Random();

  Future<Map<String, dynamic>> createReview({
    required String idToken,
    String? role,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final vendorId = _requiredString(payload, 'vendorId');
    final projectName =
        _optionalString(payload, 'projectName') ?? 'Project Review';
    final chatRoomId = _optionalString(payload, 'chatRoomId') ?? '';
    final now = _nowIso();

    final overall = _ratingValue(
      payload,
      key: 'overallRating',
      fallback: _asInt(payload['rating']) ?? 0,
    );
    if (overall <= 0) {
      throw ApiException.badRequest(
          'overallRating is required and must be 1..5.');
    }

    final quality = _ratingValue(payload, key: 'quality', fallback: overall);
    final communication =
        _ratingValue(payload, key: 'communication', fallback: overall);
    final timeliness =
        _ratingValue(payload, key: 'timeliness', fallback: overall);
    final value = _ratingValue(payload, key: 'value', fallback: overall);

    final reviewId =
        _optionalString(payload, 'reviewId') ?? _nextId(prefix: 'r');
    final reviewData = <String, dynamic>{
      'reviewId': reviewId,
      'customerId': actor.uid,
      'vendorId': vendorId,
      'projectName': projectName,
      'chatRoomId': chatRoomId,
      'overallRating': overall,
      'quality': quality,
      'communication': communication,
      'timeliness': timeliness,
      'value': value,
      'reviewText': _optionalString(payload, 'reviewText') ?? '',
      'photoUrls': _readStringList(payload['photoUrls']),
      'timestamp': now,
      'createdAt': now,
      'reviewerRole': actor.role,
    };
    if (payload.containsKey('jobId')) {
      reviewData['jobId'] = _optionalString(payload, 'jobId') ?? '';
    }

    await _firestoreClient.setDocument(
      collectionPath: 'reviews',
      documentId: reviewId,
      idToken: idToken,
      data: reviewData,
    );

    final vendorCollection = await _resolveVendorCollection(
      idToken: idToken,
      vendorId: vendorId,
    );
    await _firestoreClient.setDocument(
      collectionPath: '$vendorCollection/$vendorId/reviews',
      documentId: reviewId,
      idToken: idToken,
      data: reviewData,
    );

    final summary = await _recalculateVendorSummary(
      idToken: idToken,
      vendorCollection: vendorCollection,
      vendorId: vendorId,
    );

    final updatedTargets = await _markProjectRatedAndCompleted(
      idToken: idToken,
      actor: actor,
      chatRoomId: chatRoomId,
      explicitJobId: _optionalString(payload, 'jobId'),
    );

    return <String, dynamic>{
      'review': reviewData,
      'vendorSummary': summary,
      'updatedAt': now,
      ...updatedTargets,
    };
  }

  Future<Map<String, dynamic>> _recalculateVendorSummary({
    required String idToken,
    required String vendorCollection,
    required String vendorId,
  }) async {
    String? token;
    var loops = 0;
    var total = 0;
    var sumOverall = 0.0;
    var sumQuality = 0.0;
    var sumComm = 0.0;
    var sumTime = 0.0;
    var sumValue = 0.0;

    while (loops < 50) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: '$vendorCollection/$vendorId/reviews',
        idToken: idToken,
        pageSize: 100,
        orderBy: 'createdAt desc',
        pageToken: token,
      );
      for (final review in page.documents) {
        total++;
        sumOverall += _asDouble(review['overallRating']) ?? 0.0;
        sumQuality += _asDouble(review['quality']) ?? 0.0;
        sumComm += _asDouble(review['communication']) ?? 0.0;
        sumTime += _asDouble(review['timeliness']) ?? 0.0;
        sumValue += _asDouble(review['value']) ?? 0.0;
      }
      loops++;
      token = page.nextPageToken;
      if (token == null || page.documents.isEmpty) break;
    }

    final vendor = await _firestoreClient.getDocument(
          collectionPath: vendorCollection,
          documentId: vendorId,
          idToken: idToken,
        ) ??
        <String, dynamic>{};

    final divisor = total <= 0 ? 1 : total;
    final summary = <String, dynamic>{
      'rating': _round1(sumOverall / divisor),
      'ratingQuality': _round1(sumQuality / divisor),
      'ratingComm': _round1(sumComm / divisor),
      'ratingTimeliness': _round1(sumTime / divisor),
      'ratingValue': _round1(sumValue / divisor),
      'reviewCount': total,
      'completedWorks': _asInt(vendor['completedWorks']) != null
          ? max((_asInt(vendor['completedWorks']) ?? 0), total)
          : total,
      'updatedAt': _nowIso(),
    };

    await _firestoreClient.setDocument(
      collectionPath: vendorCollection,
      documentId: vendorId,
      idToken: idToken,
      data: <String, dynamic>{...vendor, ...summary},
    );

    return summary;
  }

  Future<Map<String, dynamic>> _markProjectRatedAndCompleted({
    required String idToken,
    required _Actor actor,
    required String chatRoomId,
    required String? explicitJobId,
  }) async {
    final out = <String, dynamic>{};
    final now = _nowIso();

    if (chatRoomId.trim().isNotEmpty) {
      final room = await _firestoreClient.getDocument(
        collectionPath: 'chatRooms',
        documentId: chatRoomId.trim(),
        idToken: idToken,
      );
      if (room != null) {
        final voteKey =
            actor.isCustomer ? 'customerStatusVote' : 'vendorStatusVote';
        final merged = <String, dynamic>{
          ...room,
          'projectStatus': 'completed',
          voteKey: 'completed',
          if (actor.isCustomer) 'customerRated': true,
          if (!actor.isCustomer) 'vendorRated': true,
          'ratedAt': now,
          'updatedAt': now,
        };
        await _firestoreClient.setDocument(
          collectionPath: 'chatRooms',
          documentId: chatRoomId.trim(),
          idToken: idToken,
          data: merged,
        );
        out['chatRoomId'] = chatRoomId.trim();
        out['chatUpdated'] = true;
      }

      final active = await _firestoreClient.getDocument(
        collectionPath: 'activeProjects',
        documentId: chatRoomId.trim(),
        idToken: idToken,
      );
      if (active != null) {
        await _firestoreClient.setDocument(
          collectionPath: 'activeProjects',
          documentId: chatRoomId.trim(),
          idToken: idToken,
          data: <String, dynamic>{
            ...active,
            'projectStatus': 'completed',
            'status': 'completed',
            'progress': 100,
            if (actor.isCustomer) 'customerRated': true,
            if (!actor.isCustomer) 'vendorRated': true,
            'ratedAt': now,
            'updatedAt': now,
          },
        );
        out['activeProjectUpdated'] = true;
      }
    }

    var jobId = explicitJobId?.trim() ?? '';
    if (jobId.isEmpty && chatRoomId.trim().isNotEmpty) {
      jobId = await _resolveJobIdFromChat(
        idToken: idToken,
        chatRoomId: chatRoomId.trim(),
      );
    }

    if (jobId.isNotEmpty) {
      final job = await _firestoreClient.getDocument(
        collectionPath: 'job_posts',
        documentId: jobId,
        idToken: idToken,
      );
      if (job != null) {
        await _firestoreClient.setDocument(
          collectionPath: 'job_posts',
          documentId: jobId,
          idToken: idToken,
          data: <String, dynamic>{
            ...job,
            'status': 'completed',
            if (actor.isCustomer) 'customerRated': true,
            if (!actor.isCustomer) 'vendorRated': true,
            'ratedAt': now,
            'updatedAt': now,
          },
        );
        out['jobId'] = jobId;
        out['jobUpdated'] = true;
      }
    }

    return out;
  }

  Future<String> _resolveJobIdFromChat({
    required String idToken,
    required String chatRoomId,
  }) async {
    final active = await _firestoreClient.getDocument(
      collectionPath: 'activeProjects',
      documentId: chatRoomId,
      idToken: idToken,
    );
    final activeJob = '${active?['jobId'] ?? ''}'.trim();
    if (activeJob.isNotEmpty) return activeJob;

    final messages = await _firestoreClient.listDocuments(
      collectionPath: 'chatRooms/$chatRoomId/messages',
      idToken: idToken,
      pageSize: 300,
      orderBy: 'timestamp desc',
    );
    for (final msg in messages) {
      if (msg['isQuoteRequest'] != true) continue;
      final quoteData =
          _mapOrNull(msg['quoteData']) ?? const <String, dynamic>{};
      final jobId = '${quoteData['jobId'] ?? ''}'.trim();
      if (jobId.isNotEmpty) return jobId;
    }
    return '';
  }

  Future<String> _resolveVendorCollection({
    required String idToken,
    required String vendorId,
  }) async {
    final vendor = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: vendorId.trim(),
      idToken: idToken,
    );
    if (vendor != null) return 'vendors';

    final artisan = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: vendorId.trim(),
      idToken: idToken,
    );
    if (artisan != null) return 'artisans';

    throw ApiException.notFound('Vendor not found.');
  }

  Future<_Actor> _resolveActor({
    required String idToken,
    String? roleHint,
  }) async {
    final uid = await _resolveUid(idToken);
    final hint = roleHint?.trim().toLowerCase();

    if (hint == 'customer') {
      return _Actor(uid: uid, role: 'customer', isCustomer: true);
    }

    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('customers', 'customer'),
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        return _Actor(
          uid: uid,
          role: pair.value,
          isCustomer: pair.value == 'customer',
        );
      }
    }

    return _Actor(
      uid: uid,
      role: hint == 'customer' ? 'customer' : 'vendor',
      isCustomer: hint == 'customer',
    );
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  int _ratingValue(
    Map<String, dynamic> payload, {
    required String key,
    required int fallback,
  }) {
    final raw = _asInt(payload[key]) ?? fallback;
    if (raw < 1) return 0;
    if (raw > 5) return 5;
    return raw;
  }

  double _round1(double v) => double.parse(v.toStringAsFixed(1));

  String _nextId({required String prefix}) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
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

class _Actor {
  const _Actor({
    required this.uid,
    required this.role,
    required this.isCustomer,
  });

  final String uid;
  final String role;
  final bool isCustomer;
}
