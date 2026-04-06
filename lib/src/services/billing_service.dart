import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';

final billingService = BillingService();

class BillingService {
  BillingService({
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

  Future<Map<String, dynamic>> createTransactionWp({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final paymentType = _optionalString(payload, 'paymentType') ?? 'premium';
    final transactionId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'transactionId') ??
        _nextId('tx');
    final now = _nowIso();

    var imageUrl = _optionalString(payload, 'imageUrl') ?? '';
    final mediaBase64 = _optionalString(payload, 'mediaBase64');
    if (mediaBase64 != null && mediaBase64.isNotEmpty) {
      final uploaded = await _mediaService.uploadForPath(
        idToken: idToken,
        mediaBase64: mediaBase64,
        folder: 'receipts',
        defaultNamePrefix: transactionId,
        contentType: _optionalString(payload, 'contentType'),
        fileName: _optionalString(payload, 'fileName'),
      );
      imageUrl = '${uploaded['downloadUrl'] ?? ''}';
    }

    final data = <String, dynamic>{
      'id': transactionId,
      'userId': uid,
      'imageUrl': imageUrl,
      'amount':
          _numeric(payload['amount']) ?? _numeric(payload['totAmount']) ?? 0.0,
      'isConfirmed': payload['isConfirmed'] == true,
      'processed': payload['processed'] == true,
      'timestamp': now,
      'createdAt': now,
      'updatedAt': now,
      'paymentType': paymentType,
      'status': _optionalString(payload, 'status') ??
          ((payload['isConfirmed'] == true) ? 'approved' : 'pending'),
      if (payload['packageData'] is Map) 'packageData': payload['packageData'],
      if (payload['metadata'] is Map) 'metadata': payload['metadata'],
    };

    await _firestoreClient.setDocument(
      collectionPath: 'transactionswp/$uid/$paymentType',
      documentId: transactionId,
      idToken: idToken,
      data: data,
    );

    return <String, dynamic>{
      'collectionPath': 'transactionswp/$uid/$paymentType',
      'transaction': data,
    };
  }

  Future<Map<String, dynamic>> getSubscriptionStatus({
    required String idToken,
    String? userId,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    if (targetUid.isEmpty) throw ApiException.badRequest('userId is required.');

    Map<String, dynamic>? doc;
    String foundCollection = '';
    String foundRole = '';
    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
      MapEntry<String, String>('customers', 'customer'),
      MapEntry<String, String>('users', 'user'),
    ]) {
      final d = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: targetUid,
        idToken: idToken,
      );
      if (d != null) {
        doc = d;
        foundCollection = pair.key;
        foundRole = pair.value;
        break;
      }
    }

    if (doc == null) {
      throw ApiException.notFound(
          'User profile not found for subscription status.');
    }

    // Mirror the Flutter logic exactly:
    // 1. No datePayed → not active
    // 2. subscriptionStatus == 'Free' → not active
    // 3. datePayed older than 30 days → expire to Free and return not active
    // 4. Otherwise → active
    final datePayed = doc['datePayed']?.toString().trim() ?? '';
    final currentStatus = doc['subscriptionStatus']?.toString().trim() ?? '';
    final now = DateTime.now().toUtc();

    bool isActive = false;
    String resolvedStatus = currentStatus;
    int daysRemaining = 0;

    if (datePayed.isNotEmpty && currentStatus != 'Free') {
      final payedDate = DateTime.tryParse(datePayed)?.toUtc();
      if (payedDate != null) {
        final daysSincePayed = now.difference(payedDate).inDays;
        if (daysSincePayed >= 30) {
          // Auto-expire: update Firestore to Free.
          resolvedStatus = 'Free';
          isActive = false;
          await _firestoreClient.setDocument(
            collectionPath: foundCollection,
            documentId: targetUid,
            idToken: idToken,
            data: <String, dynamic>{
              ...doc,
              'subscriptionStatus': 'Free',
              'updatedAt': now.toIso8601String(),
            },
          );
        } else {
          isActive = true;
          daysRemaining = 30 - daysSincePayed;
        }
      }
    }

    return <String, dynamic>{
      'userId': targetUid,
      'role': foundRole,
      'isActive': isActive,
      'subscriptionStatus': resolvedStatus,
      'datePayed': datePayed,
      'daysRemaining': daysRemaining,
      'expiresIn': doc['expiresIn'] ?? '',
      'isVerified': doc['isVerified'] == true,
      'lastPaymentType': doc['lastPaymentType'] ?? '',
    };
  }

  Future<Map<String, dynamic>> activateSubscription({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final targetUid = _optionalString(payload, 'userId');
    if (targetUid == null || targetUid.isEmpty) {
      throw ApiException.badRequest('userId is required.');
    }
    await _activateSubscription(
      idToken: idToken,
      targetUid: targetUid,
      paymentType: _optionalString(payload, 'paymentType') ?? 'premium',
      packageData: _mapOrNull(payload['packageData']),
    );
    return await getSubscriptionStatus(idToken: idToken, userId: targetUid);
  }

  Future<Map<String, dynamic>> listTransactionsWp({
    required String idToken,
    String? paymentType,
    String? userId,
    int limit = 30,
    String? pageToken,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    if (targetUid.isEmpty) throw ApiException.badRequest('userId is required.');
    final safeLimit = limit.clamp(1, 200).toInt();

    if (paymentType != null && paymentType.trim().isNotEmpty) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: 'transactionswp/$targetUid/${paymentType.trim()}',
        idToken: idToken,
        pageSize: safeLimit,
        orderBy: 'timestamp desc',
        pageToken: pageToken,
      );
      return <String, dynamic>{
        'items': page.documents,
        'count': page.documents.length,
        'paymentType': paymentType.trim(),
        if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
      };
    }

    final types = <String>{'premium', 'Premium', 'Ads', 'ads'};
    final out = <Map<String, dynamic>>[];
    for (final type in types) {
      final docs = await _firestoreClient.listDocuments(
        collectionPath: 'transactionswp/$targetUid/$type',
        idToken: idToken,
        pageSize: safeLimit,
        orderBy: 'timestamp desc',
      );
      for (final doc in docs) {
        out.add(<String, dynamic>{
          ...doc,
          'paymentType': doc['paymentType'] ?? type
        });
      }
    }

    out.sort((a, b) =>
        _timestampMs(b['timestamp']).compareTo(_timestampMs(a['timestamp'])));
    final items = out.take(safeLimit).toList();
    return <String, dynamic>{'items': items, 'count': items.length};
  }

  Future<Map<String, dynamic>> getTransactionWp({
    required String idToken,
    required String paymentType,
    required String transactionId,
    String? userId,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    final tx = await _firestoreClient.getDocument(
      collectionPath: 'transactionswp/$targetUid/${paymentType.trim()}',
      documentId: transactionId.trim(),
      idToken: idToken,
    );
    if (tx == null) throw ApiException.notFound('Transaction not found.');
    return <String, dynamic>{'id': transactionId.trim(), ...tx};
  }

  Future<Map<String, dynamic>> updateTransactionWp({
    required String idToken,
    required String paymentType,
    required String transactionId,
    required Map<String, dynamic> payload,
    String? userId,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    final type = paymentType.trim();
    final id = transactionId.trim();
    if (type.isEmpty || id.isEmpty) {
      throw ApiException.badRequest(
          'paymentType and transactionId are required.');
    }

    final existing = await _firestoreClient.getDocument(
      collectionPath: 'transactionswp/$targetUid/$type',
      documentId: id,
      idToken: idToken,
    );
    if (existing == null) throw ApiException.notFound('Transaction not found.');

    final merged = <String, dynamic>{
      ...existing,
      ...payload,
      'updatedAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'transactionswp/$targetUid/$type',
      documentId: id,
      idToken: idToken,
      data: merged,
    );

    final shouldApply = payload['applySubscription'] == true &&
        (merged['isConfirmed'] == true || payload['isConfirmed'] == true);
    if (shouldApply) {
      await _activateSubscription(
        idToken: idToken,
        targetUid: targetUid,
        paymentType: type,
        packageData: _mapOrNull(merged['packageData']),
      );
    }

    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> createPendingTransaction({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final transactionId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'transactionId') ??
        _optionalString(payload, 'referenceID') ??
        _nextId('pending');
    final now = _nowIso();

    var imageUrl = _optionalString(payload, 'imageUrl') ?? '';
    final mediaBase64 = _optionalString(payload, 'mediaBase64');
    if (mediaBase64 != null && mediaBase64.isNotEmpty) {
      final uploaded = await _mediaService.uploadForPath(
        idToken: idToken,
        mediaBase64: mediaBase64,
        folder: 'receipts',
        defaultNamePrefix: 'pending_$transactionId',
        contentType: _optionalString(payload, 'contentType'),
        fileName: _optionalString(payload, 'fileName'),
      );
      imageUrl = '${uploaded['downloadUrl'] ?? ''}';
    }

    final base = <String, dynamic>{
      'id': transactionId,
      'transactionId': transactionId,
      'referenceID': transactionId,
      'userId': uid,
      'imageUrl': imageUrl,
      'amount':
          _numeric(payload['amount']) ?? _numeric(payload['totAmount']) ?? 0.0,
      'isConfirmed': payload['isConfirmed'] == true,
      'customerConfirmed': payload['customerConfirmed'] == true,
      'timestamp': now,
      'createdAt': now,
      'updatedAt': now,
      'status': _optionalString(payload, 'status') ?? 'pending',
      if (payload['sellerId'] != null) 'sellerId': payload['sellerId'],
      if (payload['cartItems'] is List) 'cartItems': payload['cartItems'],
      if (payload['isDelivery'] != null) 'isDelivery': payload['isDelivery'],
      if (payload['note'] != null) 'note': payload['note'],
      if (payload['customerLat'] != null) 'customerLat': payload['customerLat'],
      if (payload['customerLng'] != null) 'customerLng': payload['customerLng'],
      if (payload['address'] != null) 'address': payload['address'],
      if (payload['specificAddress'] != null)
        'specificAddress': payload['specificAddress'],
      if (payload['shopName'] != null) 'shopName': payload['shopName'],
      if (payload['bank'] != null) 'bank': payload['bank'],
      if (payload['accountName'] != null) 'accountName': payload['accountName'],
      if (payload['accountNo'] != null) 'accountNo': payload['accountNo'],
      if (payload['myShare'] != null) 'myShare': payload['myShare'],
    };

    await _firestoreClient.setDocument(
      collectionPath: 'transactions',
      documentId: transactionId,
      idToken: idToken,
      data: base,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'pendingTransactions',
      documentId: uid,
      idToken: idToken,
      data: base,
    );
    if (uid != transactionId) {
      await _firestoreClient.setDocument(
        collectionPath: 'pendingTransactions',
        documentId: transactionId,
        idToken: idToken,
        data: base,
      );
    }

    return <String, dynamic>{
      'transaction': base,
      'writes': <String>[
        'transactions/$transactionId',
        'pendingTransactions/$uid',
        if (uid != transactionId) 'pendingTransactions/$transactionId',
      ],
    };
  }

  Future<Map<String, dynamic>> getPendingTransaction({
    required String idToken,
    String? userId,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'pendingTransactions',
      documentId: targetUid,
      idToken: idToken,
    );
    if (doc == null) {
      throw ApiException.notFound('Pending transaction not found.');
    }
    return <String, dynamic>{'id': targetUid, ...doc};
  }

  Future<Map<String, dynamic>> listPendingTransactions({
    required String idToken,
    int limit = 50,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'pendingTransactions',
      idToken: idToken,
      pageSize: limit.clamp(1, 200).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    final deduped = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in page.documents) {
      final key = '${item['transactionId'] ?? item['id'] ?? ''}'.trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) continue;
      deduped.add(item);
      if (deduped.length >= limit.clamp(1, 200).toInt()) break;
    }
    return <String, dynamic>{
      'items': deduped,
      'count': deduped.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> updatePendingTransaction({
    required String idToken,
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final targetUid = userId.trim();
    if (targetUid.isEmpty) throw ApiException.badRequest('userId is required.');

    final pending = await _firestoreClient.getDocument(
      collectionPath: 'pendingTransactions',
      documentId: targetUid,
      idToken: idToken,
    );
    if (pending == null)
      throw ApiException.notFound('Pending transaction not found.');
    final transactionId =
        '${pending['transactionId'] ?? pending['id'] ?? ''}'.trim();
    if (transactionId.isEmpty) {
      throw ApiException.server(
          'Pending transaction does not have a transaction id.');
    }

    final merged = <String, dynamic>{
      ...pending,
      ...payload,
      'updatedAt': _nowIso()
    };
    await _firestoreClient.setDocument(
      collectionPath: 'pendingTransactions',
      documentId: targetUid,
      idToken: idToken,
      data: merged,
    );
    if (targetUid != transactionId) {
      final byTransactionId = await _firestoreClient.getDocument(
        collectionPath: 'pendingTransactions',
        documentId: transactionId,
        idToken: idToken,
      );
      if (byTransactionId != null) {
        await _firestoreClient.setDocument(
          collectionPath: 'pendingTransactions',
          documentId: transactionId,
          idToken: idToken,
          data: <String, dynamic>{
            ...byTransactionId,
            ...payload,
            'updatedAt': _nowIso()
          },
        );
      }
    }

    final txn = await _firestoreClient.getDocument(
      collectionPath: 'transactions',
      documentId: transactionId,
      idToken: idToken,
    );
    if (txn != null) {
      await _firestoreClient.setDocument(
        collectionPath: 'transactions',
        documentId: transactionId,
        idToken: idToken,
        data: <String, dynamic>{...txn, ...payload, 'updatedAt': _nowIso()},
      );
    }

    return <String, dynamic>{'id': targetUid, ...merged};
  }

  Future<Map<String, dynamic>> createPayrollEntry({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = _optionalString(payload, 'id') ?? _nextId('payroll');
    final now = _nowIso();
    final item = <String, dynamic>{
      'id': id,
      'sellerId': _optionalString(payload, 'sellerId') ?? '',
      'orderId': _optionalString(payload, 'orderId') ?? '',
      'bank': _optionalString(payload, 'bank') ?? '',
      'accountName': _optionalString(payload, 'accountName') ?? '',
      'accountNo': _optionalString(payload, 'accountNo') ?? '',
      'amount': _numeric(payload['amount']) ?? 0.0,
      'myShare': _numeric(payload['myShare']) ?? 0.0,
      'sent': payload['sent'] == true,
      'isRead': payload['isRead'] == true,
      'isDelivery': payload['isDelivery'] == true,
      'status': _optionalString(payload, 'status') ?? 'pending',
      'timestamp': now,
      'createdAt': now,
      'updatedAt': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'Pay/PayRoll/PayRoll',
      documentId: id,
      idToken: idToken,
      data: item,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
      data: item,
    );
    return item;
  }

  Future<Map<String, dynamic>> listPayrollEntries({
    required String idToken,
    int limit = 100,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'payroll',
      idToken: idToken,
      pageSize: limit.clamp(1, 300).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    return <String, dynamic>{
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> updatePayrollEntry({
    required String idToken,
    required String payrollId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = payrollId.trim();
    if (id.isEmpty) throw ApiException.badRequest('payrollId is required.');

    final payroll = await _firestoreClient.getDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
    );
    if (payroll == null)
      throw ApiException.notFound('Payroll entry not found.');

    final merged = <String, dynamic>{
      ...payroll,
      ...payload,
      'updatedAt': _nowIso()
    };
    await _firestoreClient.setDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'Pay/PayRoll/PayRoll',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> createAdminPayout({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = _optionalString(payload, 'id') ?? _nextId('payout');
    final now = _nowIso();
    final payout = <String, dynamic>{
      'id': id,
      'sellerId': _optionalString(payload, 'sellerId') ?? '',
      'orderId': _optionalString(payload, 'orderId') ?? '',
      'bank': _optionalString(payload, 'bank') ?? '',
      'accountName': _optionalString(payload, 'accountName') ?? '',
      'accountNo': _optionalString(payload, 'accountNo') ?? '',
      'amount': _numeric(payload['amount']) ?? 0.0,
      'myShare': _numeric(payload['myShare']) ?? 0.0,
      'sent': payload['sent'] == true,
      'status': _optionalString(payload, 'status') ?? 'pending',
      'timestamp': now,
      'createdAt': now,
      'updatedAt': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'Admin/Admin/payouts',
      documentId: id,
      idToken: idToken,
      data: payout,
    );

    final existingPayroll = await _firestoreClient.getDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
      data: <String, dynamic>{...?existingPayroll, ...payout},
    );

    return payout;
  }

  Future<Map<String, dynamic>> listAdminPayouts({
    required String idToken,
    int limit = 100,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'Admin/Admin/payouts',
      idToken: idToken,
      pageSize: limit.clamp(1, 300).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    return <String, dynamic>{
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> updateAdminPayout({
    required String idToken,
    required String payoutId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = payoutId.trim();
    if (id.isEmpty) throw ApiException.badRequest('payoutId is required.');
    final payout = await _firestoreClient.getDocument(
      collectionPath: 'Admin/Admin/payouts',
      documentId: id,
      idToken: idToken,
    );
    if (payout == null) throw ApiException.notFound('Payout not found.');

    final merged = <String, dynamic>{
      ...payout,
      ...payload,
      'updatedAt': _nowIso()
    };
    await _firestoreClient.setDocument(
      collectionPath: 'Admin/Admin/payouts',
      documentId: id,
      idToken: idToken,
      data: merged,
    );

    final payroll = await _firestoreClient.getDocument(
      collectionPath: 'payroll',
      documentId: id,
      idToken: idToken,
    );
    if (payroll != null) {
      await _firestoreClient.setDocument(
        collectionPath: 'payroll',
        documentId: id,
        idToken: idToken,
        data: <String, dynamic>{...payroll, ...payload, 'updatedAt': _nowIso()},
      );
    }

    return <String, dynamic>{'id': id, ...merged};
  }

  Future<void> _activateSubscription({
    required String idToken,
    required String targetUid,
    required String paymentType,
    required Map<String, dynamic>? packageData,
  }) async {
    final now = DateTime.now().toUtc();
    final durationDays = _resolveDurationDays(packageData) ?? 30;
    final expiresAt = now.add(Duration(days: durationDays));
    final update = <String, dynamic>{
      'isVerified': true,
      'datePayed': now.toIso8601String(),
      'subscriptionStatus': 'active',
      'approvedAt': now.toIso8601String(),
      'subscriptionStartDate': now.toIso8601String(),
      'expiresIn': expiresAt.toIso8601String(),
      'lastPayment': now.toIso8601String(),
      'lastPaymentType': paymentType,
      'updatedAt': now.toIso8601String(),
    };

    for (final collection in const <String>[
      'vendors',
      'customers',
      'artisans',
      'users',
      'userId',
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: targetUid,
        idToken: idToken,
      );
      if (doc == null) continue;
      await _firestoreClient.setDocument(
        collectionPath: collection,
        documentId: targetUid,
        idToken: idToken,
        data: <String, dynamic>{...doc, ...update},
      );
    }
  }

  int? _resolveDurationDays(Map<String, dynamic>? packageData) {
    if (packageData == null) return null;
    final rawDuration = '${packageData['duration'] ?? ''}'.trim().toLowerCase();
    if (rawDuration.isEmpty) return null;
    final numValue = int.tryParse(rawDuration.split(' ').first);
    if (numValue == null || numValue <= 0) return null;
    if (rawDuration.contains('month')) return numValue * 30;
    if (rawDuration.contains('week')) return numValue * 7;
    return numValue;
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  int _timestampMs(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final asInt = int.tryParse(value.trim());
      if (asInt != null) return asInt;
      final asDate = DateTime.tryParse(value.trim());
      if (asDate != null) return asDate.toUtc().millisecondsSinceEpoch;
    }
    return 0;
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  double? _numeric(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
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
