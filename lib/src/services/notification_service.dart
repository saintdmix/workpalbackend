import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final notificationService = NotificationService();

class NotificationService {
  NotificationService({
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

  Future<Map<String, dynamic>> updateAppToken({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }

    final appToken = payload['appToken']?.toString().trim() ?? '';
    if (appToken.isEmpty) {
      throw ApiException.badRequest('appToken is required.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final tokenData = <String, dynamic>{
      'uid': uid,
      'appToken': appToken,
      'platform': payload['platform']?.toString().trim() ?? '',
      'updatedAt': now,
    };

    // Write to all possible profile collections so the token is always findable.
    for (final collection in const <String>[
      'artisans',
      'vendors',
      'customers',
      'users',
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        await _firestoreClient.setDocument(
          collectionPath: collection,
          documentId: uid,
          idToken: idToken,
          data: <String, dynamic>{...doc, 'appToken': appToken, 'updatedAt': now},
        );
      }
    }

    // Also store in a dedicated tokens collection for easy FCM lookup.
    await _firestoreClient.setDocument(
      collectionPath: 'app_tokens',
      documentId: uid,
      idToken: idToken,
      data: tokenData,
    );

    return <String, dynamic>{'uid': uid, 'appToken': appToken, 'updatedAt': now};
  }

  Future<List<Map<String, dynamic>>> listNotifications({
    required String role,
    required String idToken,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    final context = await _resolveUserContext(role, idToken);
    final store = await _getStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      createIfMissing: true,
    );
    if (store == null) {
      throw ApiException.internal('Failed to initialize notifications store.');
    }
    final items = _readItems(store['items']);

    var filtered = items;
    if (unreadOnly) {
      filtered = filtered.where((item) => item['read'] != true).toList();
    }

    filtered.sort((a, b) {
      final aTime = '${a['createdAt'] ?? ''}';
      final bTime = '${b['createdAt'] ?? ''}';
      return bTime.compareTo(aTime);
    });

    if (limit < filtered.length) {
      filtered = filtered.take(limit).toList();
    }

    return filtered;
  }

  Future<Map<String, dynamic>> createNotification({
    required String role,
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final context = await _resolveUserContext(role, idToken);
    final title = _requiredString(payload, 'title');
    final body = _requiredString(payload, 'body');
    final now = DateTime.now().toUtc().toIso8601String();

    final store = await _getStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      createIfMissing: true,
    );
    if (store == null) {
      throw ApiException.internal('Failed to initialize notifications store.');
    }

    final items = _readItems(store['items']);
    final item = <String, dynamic>{
      'id': _createNotificationId(),
      'title': title,
      'body': body,
      'type': _optionalString(payload, 'type') ?? 'general',
      'data': payload['data'] is Map ? payload['data'] : <String, dynamic>{},
      'read': false,
      'createdAt': now,
    };
    items.insert(0, item);

    await _saveStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      items: items,
      updatedAt: now,
    );

    return item;
  }

  Future<Map<String, dynamic>> markAsRead({
    required String role,
    required String idToken,
    required String notificationId,
  }) async {
    if (notificationId.trim().isEmpty) {
      throw ApiException.badRequest('notification_id is required.');
    }

    final context = await _resolveUserContext(role, idToken);
    final store = await _getStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      createIfMissing: false,
    );

    if (store == null) {
      throw ApiException.notFound('Notification not found.');
    }

    final items = _readItems(store['items']);
    final index = items.indexWhere(
      (item) => '${item['id']}' == notificationId.trim(),
    );

    if (index == -1) {
      throw ApiException.notFound('Notification not found.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final updatedItem = <String, dynamic>{
      ...items[index],
      'read': true,
      'readAt': now,
    };
    items[index] = updatedItem;

    await _saveStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      items: items,
      updatedAt: now,
    );

    return updatedItem;
  }

  Future<Map<String, dynamic>> markAllAsRead({
    required String role,
    required String idToken,
  }) async {
    final context = await _resolveUserContext(role, idToken);
    final store = await _getStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      createIfMissing: true,
    );
    if (store == null) {
      throw ApiException.internal('Failed to initialize notifications store.');
    }

    final items = _readItems(store['items']);
    final now = DateTime.now().toUtc().toIso8601String();
    var updatedCount = 0;

    for (var i = 0; i < items.length; i++) {
      if (items[i]['read'] == true) continue;
      items[i] = <String, dynamic>{
        ...items[i],
        'read': true,
        'readAt': now,
      };
      updatedCount++;
    }

    await _saveStoreDoc(
      role: context.role,
      uid: context.uid,
      idToken: idToken,
      items: items,
      updatedAt: now,
    );

    return <String, dynamic>{
      'updatedCount': updatedCount,
      'updatedAt': now,
    };
  }

  Future<_UserContext> _resolveUserContext(String role, String idToken) async {
    final normalizedRole = _normalizeRole(role);
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}';
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return _UserContext(role: normalizedRole, uid: uid);
  }

  Future<Map<String, dynamic>?> _getStoreDoc({
    required String role,
    required String uid,
    required String idToken,
    required bool createIfMissing,
  }) async {
    final collection = _collectionForRole(role);
    var doc = await _firestoreClient.getDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
    );

    if (doc == null && createIfMissing) {
      final now = DateTime.now().toUtc().toIso8601String();
      doc = <String, dynamic>{
        'uid': uid,
        'role': role,
        'items': <dynamic>[],
        'updatedAt': now,
      };
      await _firestoreClient.setDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
        data: doc,
      );
    }

    return doc;
  }

  Future<void> _saveStoreDoc({
    required String role,
    required String uid,
    required String idToken,
    required List<Map<String, dynamic>> items,
    required String updatedAt,
  }) async {
    await _firestoreClient.setDocument(
      collectionPath: _collectionForRole(role),
      documentId: uid,
      idToken: idToken,
      data: <String, dynamic>{
        'uid': uid,
        'role': role,
        'items': items,
        'updatedAt': updatedAt,
      },
    );
  }

  List<Map<String, dynamic>> _readItems(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        result.add(Map<String, dynamic>.from(item));
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  String _createNotificationId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return 'n_${now}_$suffix';
  }

  String _normalizeRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized != 'customer' && normalized != 'artisan') {
      throw ApiException.badRequest('role must be either customer or artisan.');
    }
    return normalized;
  }

  String _collectionForRole(String role) {
    return role == 'artisan'
        ? 'artisan_notifications'
        : 'customer_notifications';
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
}

class _UserContext {
  const _UserContext({required this.role, required this.uid});

  final String role;
  final String uid;
}
