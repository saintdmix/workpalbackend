import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final workfeedEngagementService = WorkfeedEngagementService();

class WorkfeedEngagementService {
  WorkfeedEngagementService({
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

  Future<Map<String, dynamic>> togglePostLike({
    required String idToken,
    required String postId,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final post = await _firestoreClient.getDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
    );
    if (post == null) {
      throw ApiException.notFound('Workfeed post not found.');
    }

    // Firestore REST array transforms are not used here, so we do a
    // read-modify-write to preserve existing document shape.
    final likes = _readStringList(post['likes']);
    final wasLiked = likes.contains(uid);
    if (wasLiked) {
      likes.removeWhere((id) => id == uid);
    } else {
      likes.add(uid);
    }

    await _firestoreClient.setDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
      data: <String, dynamic>{
        ...post,
        'likes': likes,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    return <String, dynamic>{
      'postId': normalizedPostId,
      'liked': !wasLiked,
      'likeCount': likes.length,
      'likes': likes,
    };
  }

  Future<List<Map<String, dynamic>>> listComments({
    required String idToken,
    required String postId,
    String? parentCommentId,
    int limit = 100,
  }) async {
    await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final safeLimit = limit.clamp(1, 300).toInt();
    final comments = await _firestoreClient.listDocuments(
      collectionPath: 'posts/$normalizedPostId/comments',
      idToken: idToken,
      pageSize: safeLimit,
      orderBy: 'timestamp asc',
    );

    final requestedParent = parentCommentId?.trim();
    final filtered = comments.where((comment) {
      final parent = '${comment['parentCommentId'] ?? ''}'.trim();
      if (requestedParent == null) return parent.isEmpty;
      if (requestedParent.isEmpty) return parent.isEmpty;
      return parent == requestedParent;
    }).toList();

    return _enrichCommentsWithProfiles(
      comments: filtered,
      idToken: idToken,
    );
  }

  Future<List<Map<String, dynamic>>> _enrichCommentsWithProfiles({
    required List<Map<String, dynamic>> comments,
    required String idToken,
  }) async {
    final uniqueIds = comments
        .map((c) => '${c['userId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final profileMap = <String, Map<String, dynamic>>{};
    for (final uid in uniqueIds) {
      for (final collection in const <String>[
        'artisans',
        'vendors',
        'customers',
      ]) {
        final doc = await _firestoreClient.getDocument(
          collectionPath: collection,
          documentId: uid,
          idToken: idToken,
        );
        if (doc != null) {
          profileMap[uid] = doc;
          break;
        }
      }
    }

    return comments.map((comment) {
      final uid = '${comment['userId'] ?? ''}'.trim();
      final profile = profileMap[uid] ?? const <String, dynamic>{};
      return <String, dynamic>{
        ...comment,
        'commenterName': comment['commenterName'] ??
            profile['name'] ??
            profile['username'] ??
            profile['displayName'] ??
            '',
        'commenterImage': comment['commenterImage'] ??
            profile['profileImageUrl'] ??
            profile['imageUrl'] ??
            profile['profileImage'] ??
            '',
      };
    }).toList();
  }

  Future<Map<String, dynamic>> createComment({
    required String idToken,
    required String postId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final text = _requiredString(payload, 'text');
    final parentCommentId = _optionalString(payload, 'parentCommentId');
    final now = DateTime.now().toUtc().toIso8601String();

    // Fetch commenter profile to embed name and image.
    Map<String, dynamic> commenterProfile = const <String, dynamic>{};
    for (final collection in const <String>['artisans', 'vendors', 'customers']) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        commenterProfile = doc;
        break;
      }
    }
    final commenterName = _optionalString(commenterProfile, 'name') ??
        _optionalString(commenterProfile, 'username') ??
        _optionalString(commenterProfile, 'displayName') ??
        '';
    final commenterImage = _optionalString(commenterProfile, 'profileImageUrl') ??
        _optionalString(commenterProfile, 'imageUrl') ??
        _optionalString(commenterProfile, 'profileImage') ??
        '';

    final created = await _firestoreClient.createDocument(
      collectionPath: 'posts/$normalizedPostId/comments',
      idToken: idToken,
      data: <String, dynamic>{
        'postId': normalizedPostId,
        'userId': uid,
        'commenterName': commenterName,
        'commenterImage': commenterImage,
        'text': text,
        'timestamp': now,
        'likes': <dynamic>[],
        'likeCount': 0,
        'replyCount': 0,
        if (parentCommentId != null) 'parentCommentId': parentCommentId,
      },
    );

    if (parentCommentId != null) {
      final parent = await _firestoreClient.getDocument(
        collectionPath: 'posts/$normalizedPostId/comments',
        documentId: parentCommentId,
        idToken: idToken,
      );
      if (parent != null) {
        final replyCount = (parent['replyCount'] as num?)?.toInt() ?? 0;
        await _firestoreClient.setDocument(
          collectionPath: 'posts/$normalizedPostId/comments',
          documentId: parentCommentId,
          idToken: idToken,
          data: <String, dynamic>{
            ...parent,
            'replyCount': replyCount + 1,
            'updatedAt': now,
          },
        );
      }
    }

    return created;
  }

  Future<Map<String, dynamic>> toggleCommentLike({
    required String idToken,
    required String postId,
    required String commentId,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    final normalizedCommentId = commentId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }
    if (normalizedCommentId.isEmpty) {
      throw ApiException.badRequest('comment_id is required.');
    }

    final comment = await _firestoreClient.getDocument(
      collectionPath: 'posts/$normalizedPostId/comments',
      documentId: normalizedCommentId,
      idToken: idToken,
    );
    if (comment == null) {
      throw ApiException.notFound('Comment not found.');
    }

    final likes = _readStringList(comment['likes']);
    final wasLiked = likes.contains(uid);
    if (wasLiked) {
      likes.removeWhere((id) => id == uid);
    } else {
      likes.add(uid);
    }

    await _firestoreClient.setDocument(
      collectionPath: 'posts/$normalizedPostId/comments',
      documentId: normalizedCommentId,
      idToken: idToken,
      data: <String, dynamic>{
        ...comment,
        'likes': likes,
        'likeCount': likes.length,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    return <String, dynamic>{
      'postId': normalizedPostId,
      'commentId': normalizedCommentId,
      'liked': !wasLiked,
      'likeCount': likes.length,
      'likes': likes,
    };
  }

  Future<Map<String, dynamic>> trackInteraction({
    required String idToken,
    required String postId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final type = '${payload['type'] ?? ''}'.trim().toLowerCase();
    if (!const <String>{'view', 'tap', 'profile_visit'}.contains(type)) {
      throw ApiException.badRequest(
        'type must be one of: view, tap, profile_visit.',
      );
    }

    final post = await _firestoreClient.getDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
    );
    if (post == null) {
      throw ApiException.notFound('Workfeed post not found.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final countKey = type == 'view'
        ? 'views'
        : type == 'tap'
            ? 'taps'
            : 'profileVisits';
    final currentCount = (post[countKey] as num?)?.toInt() ?? 0;

    await _firestoreClient.setDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
      data: <String, dynamic>{
        ...post,
        countKey: currentCount + 1,
        'updatedAt': now,
      },
    );

    await _firestoreClient.createDocument(
      collectionPath: 'post_interactions',
      idToken: idToken,
      data: <String, dynamic>{
        'postId': normalizedPostId,
        'userId': uid,
        'type': type,
        'timestamp': now,
        'artisanId': '${post['artisanId'] ?? ''}',
      },
    );

    return <String, dynamic>{
      'postId': normalizedPostId,
      'type': type,
      countKey: currentCount + 1,
    };
  }

  Future<Map<String, dynamic>> reportPost({
    required String idToken,
    required String postId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }

    final reason = _requiredString(payload, 'reason');
    final additionalDetails =
        _optionalString(payload, 'additionalDetails') ?? '';
    final post = await _firestoreClient.getDocument(
      collectionPath: 'posts',
      documentId: normalizedPostId,
      idToken: idToken,
    );
    if (post == null) {
      throw ApiException.notFound('Workfeed post not found.');
    }

    final reporter = await _resolveReporter(idToken: idToken, uid: uid);
    final now = DateTime.now().toUtc().toIso8601String();
    final postOwnerId = '${post['artisanId'] ?? ''}';
    final postType = _optionalString(payload, 'postType') ??
        _optionalString(post, 'type') ??
        'regular';

    final report = await _firestoreClient.createDocument(
      collectionPath: 'reports',
      idToken: idToken,
      data: <String, dynamic>{
        'postId': normalizedPostId,
        'postOwnerId': postOwnerId,
        'postType': postType,
        'reporterId': uid,
        'reporterName': reporter.name,
        'reporterType': reporter.type,
        'reason': reason,
        'additionalDetails': additionalDetails,
        'timestamp': now,
        'status': 'pending',
        'reviewedBy': null,
        'reviewedAt': null,
        'action': null,
      },
    );

    final adminNotification = await _firestoreClient.createDocument(
      collectionPath: 'admin_notifications',
      idToken: idToken,
      data: <String, dynamic>{
        'type': 'post_report',
        'postId': normalizedPostId,
        'reporterId': uid,
        'reason': reason,
        'timestamp': now,
        'isRead': false,
      },
    );

    return <String, dynamic>{
      'report': report,
      'adminNotification': adminNotification,
    };
  }

  Future<Map<String, dynamic>> reportComment({
    required String idToken,
    required String postId,
    required String commentId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final normalizedPostId = postId.trim();
    final normalizedCommentId = commentId.trim();
    if (normalizedPostId.isEmpty) {
      throw ApiException.badRequest('post_id is required.');
    }
    if (normalizedCommentId.isEmpty) {
      throw ApiException.badRequest('comment_id is required.');
    }

    final reason = _requiredString(payload, 'reason');
    final additionalDetails =
        _optionalString(payload, 'additionalDetails') ?? '';
    final comment = await _firestoreClient.getDocument(
      collectionPath: 'posts/$normalizedPostId/comments',
      documentId: normalizedCommentId,
      idToken: idToken,
    );
    if (comment == null) {
      throw ApiException.notFound('Comment not found.');
    }

    final reporter = await _resolveReporter(idToken: idToken, uid: uid);
    final now = DateTime.now().toUtc().toIso8601String();
    final commentOwnerId = '${comment['userId'] ?? ''}';

    final report = await _firestoreClient.createDocument(
      collectionPath: 'comment_reports',
      idToken: idToken,
      data: <String, dynamic>{
        'postId': normalizedPostId,
        'commentId': normalizedCommentId,
        'commentOwnerId': commentOwnerId,
        'reporterId': uid,
        'reporterName': reporter.name,
        'reporterType': reporter.type,
        'reason': reason,
        'additionalDetails': additionalDetails,
        'timestamp': now,
        'status': 'pending',
        'reviewedBy': null,
        'reviewedAt': null,
        'action': null,
      },
    );

    final adminNotification = await _firestoreClient.createDocument(
      collectionPath: 'admin_notifications',
      idToken: idToken,
      data: <String, dynamic>{
        'type': 'comment_report',
        'postId': normalizedPostId,
        'commentId': normalizedCommentId,
        'reporterId': uid,
        'reason': reason,
        'timestamp': now,
        'isRead': false,
      },
    );

    return <String, dynamic>{
      'report': report,
      'adminNotification': adminNotification,
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

  Future<_ReporterIdentity> _resolveReporter({
    required String idToken,
    required String uid,
  }) async {
    final vendor = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: uid,
      idToken: idToken,
    );
    if (vendor != null) {
      return _ReporterIdentity(
        name: _optionalString(vendor, 'name') ?? 'Anonymous',
        type: 'vendor',
      );
    }

    final artisan = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: uid,
      idToken: idToken,
    );
    if (artisan != null) {
      return _ReporterIdentity(
        name: _optionalString(artisan, 'name') ?? 'Anonymous',
        type: 'artisan',
      );
    }

    final customer = await _firestoreClient.getDocument(
      collectionPath: 'customers',
      documentId: uid,
      idToken: idToken,
    );
    if (customer != null) {
      return _ReporterIdentity(
        name: _optionalString(customer, 'username') ??
            _optionalString(customer, 'name') ??
            'Anonymous',
        type: 'customer',
      );
    }

    return const _ReporterIdentity(name: 'Anonymous', type: 'unknown');
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final result = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(item.trim());
      }
    }
    return result;
  }

  String _requiredString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw ApiException.badRequest('$key is required.');
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}

class _ReporterIdentity {
  const _ReporterIdentity({required this.name, required this.type});

  final String name;
  final String type;
}
