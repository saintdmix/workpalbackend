import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/utils/notification_types.dart';

final notificationParityService = NotificationParityService();

class NotificationParityService {
  NotificationParityService({
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
  final Random _random = Random();

  Future<Map<String, dynamic>> listNotifications({
    required String idToken,
    String schema = 'wp',
    String? targetUserId,
    String adminDocId = 'Admin',
    int limit = 30,
    bool unreadOnly = false,
    String? pageToken,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final kind = _parseSchema(schema);
    final safeLimit = limit.clamp(1, 200);
    final target = _resolveTargetUid(
      actorUid: actorUid,
      targetUserId: targetUserId,
      schema: kind,
      adminDocId: adminDocId,
    );

    if (kind == _NotificationSchema.flat) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: 'notifications',
        idToken: idToken,
        pageSize: max(safeLimit * 3, 80),
        orderBy: 'timestamp desc',
        pageToken: pageToken,
      );
      final items = <Map<String, dynamic>>[];
      for (final doc in page.documents) {
        if ('${doc['userId'] ?? ''}'.trim() != target) continue;
        if (unreadOnly && _isRead(doc)) continue;
        items.add(_decorateNotification(doc));
      }
      return <String, dynamic>{
        'schema': kind.value,
        'target': target,
        'items': items.take(safeLimit).toList(),
        'count': min(items.length, safeLimit),
        if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
      };
    }

    final collectionPath = _collectionPath(
      schema: kind,
      target: target,
      adminDocId: adminDocId,
    );
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: collectionPath,
      idToken: idToken,
      pageSize: safeLimit,
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    final items = page.documents
        .where((n) => !(unreadOnly && _isRead(n)))
        .map(_decorateNotification)
        .toList();
    return <String, dynamic>{
      'schema': kind.value,
      'target': target,
      'items': items,
      'count': items.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createNotification({
    required String idToken,
    required Map<String, dynamic> payload,
    String schema = 'wp',
    String? targetUserId,
    String adminDocId = 'Admin',
  }) async {
    final actorUid = await _resolveUid(idToken);
    final kind = _parseSchema(schema);
    final target = _resolveTargetUid(
      actorUid: actorUid,
      targetUserId: targetUserId ?? _optionalString(payload, 'userId'),
      schema: kind,
      adminDocId: adminDocId,
    );

    final title = _requiredString(payload, 'title');
    final body = _requiredString(payload, 'body');
    final type = _normalizeNotificationType(payload);
    final notificationId =
        _optionalString(payload, 'id') ?? _nextId(prefix: 'n');
    final nowIso = _nowIso();

    final data = <String, dynamic>{
      'id': notificationId,
      'title': title,
      'body': body,
      'type': type,
      'typeLabel': notificationTypeLabel(type),
      'typeDescription': notificationTypeDescription(type),
      'timestamp': nowIso,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'isRead': false,
      'read': false,
      if (payload['data'] is Map) 'data': payload['data'],
      if (_optionalString(payload, 'chatRoomId') != null)
        'chatRoomId': _optionalString(payload, 'chatRoomId'),
      if (_optionalString(payload, 'senderId') != null)
        'senderId': _optionalString(payload, 'senderId'),
      if (kind == _NotificationSchema.flat) 'userId': target,
    };

    if (kind == _NotificationSchema.flat) {
      await _firestoreClient.createDocument(
        collectionPath: 'notifications',
        idToken: idToken,
        documentId: notificationId,
        data: data,
      );
      return <String, dynamic>{
        'schema': kind.value,
        'target': target,
        ..._decorateNotification(data),
      };
    }

    final path = _collectionPath(
      schema: kind,
      target: target,
      adminDocId: adminDocId,
    );
    await _firestoreClient.setDocument(
      collectionPath: path,
      documentId: notificationId,
      idToken: idToken,
      data: data,
    );
    return <String, dynamic>{
      'schema': kind.value,
      'target': target,
      ..._decorateNotification(data),
    };
  }

  Future<Map<String, dynamic>> markAsRead({
    required String idToken,
    required String notificationId,
    String schema = 'wp',
    String? targetUserId,
    String adminDocId = 'Admin',
  }) async {
    final actorUid = await _resolveUid(idToken);
    final kind = _parseSchema(schema);
    final target = _resolveTargetUid(
      actorUid: actorUid,
      targetUserId: targetUserId,
      schema: kind,
      adminDocId: adminDocId,
    );

    if (kind == _NotificationSchema.flat) {
      final updated = await _markFlatRead(
        idToken: idToken,
        targetUserId: target,
        notificationId: notificationId.trim(),
      );
      return <String, dynamic>{
        'schema': kind.value,
        'target': target,
        ..._decorateNotification(updated),
      };
    }

    final path = _collectionPath(
      schema: kind,
      target: target,
      adminDocId: adminDocId,
    );
    final id = notificationId.trim();
    final current = await _firestoreClient.getDocument(
      collectionPath: path,
      documentId: id,
      idToken: idToken,
    );
    if (current == null) throw ApiException.notFound('Notification not found.');

    final updated = <String, dynamic>{
      ...current,
      'isRead': true,
      'read': true,
      'readAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: path,
      documentId: id,
      idToken: idToken,
      data: updated,
    );
    return _decorateNotification(<String, dynamic>{'id': id, ...updated});
  }

  Future<Map<String, dynamic>> markAllAsRead({
    required String idToken,
    String schema = 'wp',
    String? targetUserId,
    String adminDocId = 'Admin',
  }) async {
    final actorUid = await _resolveUid(idToken);
    final kind = _parseSchema(schema);
    final target = _resolveTargetUid(
      actorUid: actorUid,
      targetUserId: targetUserId,
      schema: kind,
      adminDocId: adminDocId,
    );

    final now = _nowIso();
    var updatedCount = 0;

    if (kind == _NotificationSchema.flat) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: 'notifications',
        idToken: idToken,
        pageSize: 300,
        orderBy: 'timestamp desc',
      );
      for (final doc in page.documents) {
        if ('${doc['userId'] ?? ''}'.trim() != target) continue;
        if (_isRead(doc)) continue;
        final id = '${doc['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        await _firestoreClient.setDocument(
          collectionPath: 'notifications',
          documentId: id,
          idToken: idToken,
          data: <String, dynamic>{
            ...doc,
            'isRead': true,
            'read': true,
            'readAt': now,
          },
        );
        updatedCount++;
      }
      return <String, dynamic>{
        'schema': kind.value,
        'target': target,
        'updatedCount': updatedCount,
        'updatedAt': now,
      };
    }

    final path = _collectionPath(
      schema: kind,
      target: target,
      adminDocId: adminDocId,
    );
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: path,
      idToken: idToken,
      pageSize: 300,
      orderBy: 'timestamp desc',
    );
    for (final doc in page.documents) {
      if (_isRead(doc)) continue;
      final id = '${doc['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      await _firestoreClient.setDocument(
        collectionPath: path,
        documentId: id,
        idToken: idToken,
        data: <String, dynamic>{
          ...doc,
          'isRead': true,
          'read': true,
          'readAt': now,
        },
      );
      updatedCount++;
    }

    return <String, dynamic>{
      'schema': kind.value,
      'target': target,
      'updatedCount': updatedCount,
      'updatedAt': now,
    };
  }

  Future<Map<String, dynamic>> _markFlatRead({
    required String idToken,
    required String targetUserId,
    required String notificationId,
  }) async {
    final byId = await _firestoreClient.getDocument(
      collectionPath: 'notifications',
      documentId: notificationId,
      idToken: idToken,
    );
    if (byId != null && '${byId['userId'] ?? ''}'.trim() == targetUserId) {
      final updated = <String, dynamic>{
        ...byId,
        'isRead': true,
        'read': true,
        'readAt': _nowIso(),
      };
      await _firestoreClient.setDocument(
        collectionPath: 'notifications',
        documentId: notificationId,
        idToken: idToken,
        data: updated,
      );
      return <String, dynamic>{'id': notificationId, ...updated};
    }

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'notifications',
      idToken: idToken,
      pageSize: 300,
      orderBy: 'timestamp desc',
    );
    for (final doc in page.documents) {
      if ('${doc['userId'] ?? ''}'.trim() != targetUserId) continue;
      final docId = '${doc['id'] ?? ''}'.trim();
      if (docId != notificationId) continue;
      final updated = <String, dynamic>{
        ...doc,
        'isRead': true,
        'read': true,
        'readAt': _nowIso(),
      };
      await _firestoreClient.setDocument(
        collectionPath: 'notifications',
        documentId: docId,
        idToken: idToken,
        data: updated,
      );
      return <String, dynamic>{'id': docId, ...updated};
    }

    throw ApiException.notFound('Notification not found.');
  }

  String _resolveTargetUid({
    required String actorUid,
    required String? targetUserId,
    required _NotificationSchema schema,
    required String adminDocId,
  }) {
    if (schema == _NotificationSchema.admin) {
      final adminTarget = adminDocId.trim();
      if (adminTarget.isEmpty) {
        throw ApiException.badRequest(
          'adminDocId is required for admin schema.',
        );
      }
      return adminTarget;
    }
    final target = (targetUserId ?? actorUid).trim();
    if (target.isEmpty) {
      throw ApiException.badRequest('targetUserId is required.');
    }
    return target;
  }

  String _collectionPath({
    required _NotificationSchema schema,
    required String target,
    required String adminDocId,
  }) {
    switch (schema) {
      case _NotificationSchema.wp:
        return 'NotificationWp/$target/notification';
      case _NotificationSchema.legacy:
        return 'Notification/$target/notification';
      case _NotificationSchema.admin:
        return 'Admin/$adminDocId/notification';
      case _NotificationSchema.items:
        return 'notifications/$target/items';
      case _NotificationSchema.flat:
        return 'notifications';
    }
  }

  _NotificationSchema _parseSchema(String schema) {
    final normalized = schema.trim().toLowerCase();
    switch (normalized) {
      case 'wp':
      case 'notificationwp':
        return _NotificationSchema.wp;
      case 'legacy':
      case 'notification':
        return _NotificationSchema.legacy;
      case 'admin':
        return _NotificationSchema.admin;
      case 'items':
      case 'nested':
        return _NotificationSchema.items;
      case 'flat':
      case 'notifications':
        return _NotificationSchema.flat;
      default:
        throw ApiException.badRequest(
          'schema must be one of: wp, legacy, admin, items, flat.',
        );
    }
  }

  bool _isRead(Map<String, dynamic> doc) {
    if (doc['isRead'] == true) return true;
    if (doc['read'] == true) return true;
    return false;
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
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

  String _normalizeNotificationType(Map<String, dynamic> payload) {
    final rawType = _optionalString(payload, 'type');
    if (rawType == null) return notificationTypeGeneral;

    final normalized = canonicalizeNotificationType(rawType);
    if (normalized != null) return normalized;

    throw ApiException.badRequest(
      'type must be one of: ${notificationTypeValuesText()}.',
    );
  }

  Map<String, dynamic> _decorateNotification(Map<String, dynamic> item) {
    final type =
        canonicalizeNotificationType('${item['type'] ?? ''}') ??
        notificationTypeGeneral;
    return <String, dynamic>{
      ...item,
      'type': type,
      'typeLabel': notificationTypeLabel(type),
      'typeDescription': notificationTypeDescription(type),
    };
  }

  String _nextId({required String prefix}) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}

enum _NotificationSchema {
  wp('wp'),
  legacy('legacy'),
  admin('admin'),
  items('items'),
  flat('flat')
  ;

  const _NotificationSchema(this.value);
  final String value;
}
