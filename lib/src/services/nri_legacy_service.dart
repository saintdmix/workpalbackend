import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';

final nriLegacyService = NriLegacyService();

class NriLegacyService {
  NriLegacyService({
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

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      final map = _asMap(item);
      if (map != null) out.add(map);
    }
    return out;
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  String _requiredString(
    Map<String, dynamic> payload,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    for (final field in <String>[key, ...aliases]) {
      final value = payload[field];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    throw ApiException.badRequest(
        '${[key, ...aliases].join('/')} is required.');
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

  String _nextId(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Future<String?> _uploadOne({
    required String idToken,
    required String folder,
    String? mediaBase64,
    String? fileName,
    String? contentType,
  }) async {
    final raw = mediaBase64?.trim() ?? '';
    if (raw.isEmpty) return null;
    final upload = await _mediaService.uploadForPath(
      idToken: idToken,
      mediaBase64: raw,
      folder: folder,
      defaultNamePrefix: _nextId('file'),
      fileName: fileName,
      contentType: contentType,
    );
    return '${upload['downloadUrl'] ?? ''}';
  }

  Future<Map<String, dynamic>> getUserCart({
    required String idToken,
    required String uid,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    if (userId.isEmpty) throw ApiException.badRequest('uid is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'legacyUserNodes',
      documentId: userId,
      idToken: idToken,
    );
    if (doc == null) return <String, dynamic>{};
    final cart = _asMap(doc['cart']) ?? <String, dynamic>{};
    return cart;
  }

  Future<Map<String, dynamic>> putUserCart({
    required String idToken,
    required String uid,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    if (userId.isEmpty) throw ApiException.badRequest('uid is required.');
    final existing = await _firestoreClient.getDocument(
          collectionPath: 'legacyUserNodes',
          documentId: userId,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    final cart = <String, dynamic>{...payload};
    await _firestoreClient.setDocument(
      collectionPath: 'legacyUserNodes',
      documentId: userId,
      idToken: idToken,
      data: <String, dynamic>{
        ...existing,
        'cart': cart,
        'updatedAt': _nowIso(),
      },
    );
    return cart;
  }

  Future<Map<String, dynamic>> patchUserCart({
    required String idToken,
    required String uid,
    required Map<String, dynamic> payload,
  }) async {
    final current = await getUserCart(idToken: idToken, uid: uid);
    final merged = <String, dynamic>{...current, ...payload};
    await putUserCart(idToken: idToken, uid: uid, payload: merged);
    return merged;
  }

  Future<void> deleteUserCart({
    required String idToken,
    required String uid,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    if (userId.isEmpty) throw ApiException.badRequest('uid is required.');
    final existing = await _firestoreClient.getDocument(
      collectionPath: 'legacyUserNodes',
      documentId: userId,
      idToken: idToken,
    );
    if (existing == null) return;
    final updated = <String, dynamic>{...existing}..remove('cart');
    updated['updatedAt'] = _nowIso();
    await _firestoreClient.setDocument(
      collectionPath: 'legacyUserNodes',
      documentId: userId,
      idToken: idToken,
      data: updated,
    );
  }

  Future<Map<String, dynamic>> listUserOrders({
    required String idToken,
    required String uid,
    String? status,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    if (userId.isEmpty) throw ApiException.badRequest('uid is required.');
    final docs = await _firestoreClient.listDocuments(
      collectionPath: 'legacyUserOrders/$userId/orders',
      idToken: idToken,
      pageSize: 500,
      orderBy: 'dateTime desc',
    );

    final out = <String, dynamic>{};
    for (final doc in docs) {
      final id = '${doc['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      if (status != null &&
          status.trim().isNotEmpty &&
          '${doc['status'] ?? ''}'.trim().toLowerCase() !=
              status.trim().toLowerCase()) {
        continue;
      }
      final entry = <String, dynamic>{...doc}..remove('id');
      out[id] = entry;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getUserOrder({
    required String idToken,
    required String uid,
    required String orderId,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = orderId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and orderId are required.');
    }
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'legacyUserOrders/$userId/orders',
      documentId: id,
      idToken: idToken,
    );
    return doc;
  }

  Future<Map<String, dynamic>> upsertUserOrder({
    required String idToken,
    required String uid,
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = orderId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and orderId are required.');
    }
    final current = await _firestoreClient.getDocument(
          collectionPath: 'legacyUserOrders/$userId/orders',
          documentId: id,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      'orderId': id,
      'updatedAt': _nowIso(),
      if (!current.containsKey('createdAt')) 'createdAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'legacyUserOrders/$userId/orders',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<Map<String, dynamic>> createUserOrder({
    required String idToken,
    required String uid,
    required Map<String, dynamic> payload,
  }) async {
    final orderId = _optionalString(payload, 'orderId') ??
        _optionalString(payload, 'id') ??
        _nextId('order');
    final merged = await upsertUserOrder(
      idToken: idToken,
      uid: uid,
      orderId: orderId,
      payload: payload,
    );
    return <String, dynamic>{'id': orderId, ...merged};
  }

  Future<void> deleteUserOrder({
    required String idToken,
    required String uid,
    required String orderId,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = orderId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and orderId are required.');
    }
    await _firestoreClient.deleteDocument(
      collectionPath: 'legacyUserOrders/$userId/orders',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> listAdminOrders({
    required String idToken,
    String? status,
  }) async {
    await _resolveUid(idToken);
    final docs = await _firestoreClient.listDocuments(
      collectionPath: 'Admin/Admin/orders',
      idToken: idToken,
      pageSize: 700,
      orderBy: 'dateTime desc',
    );
    final out = <String, dynamic>{};
    for (final doc in docs) {
      final id = '${doc['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      if (status != null &&
          status.trim().isNotEmpty &&
          '${doc['status'] ?? ''}'.trim().toLowerCase() !=
              status.trim().toLowerCase()) {
        continue;
      }
      final entry = <String, dynamic>{...doc}..remove('id');
      out[id] = entry;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getAdminOrder({
    required String idToken,
    required String orderId,
  }) async {
    await _resolveUid(idToken);
    final id = orderId.trim();
    if (id.isEmpty) throw ApiException.badRequest('orderId is required.');
    return _firestoreClient.getDocument(
      collectionPath: 'Admin/Admin/orders',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> upsertAdminOrder({
    required String idToken,
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = orderId.trim();
    if (id.isEmpty) throw ApiException.badRequest('orderId is required.');
    final current = await _firestoreClient.getDocument(
          collectionPath: 'Admin/Admin/orders',
          documentId: id,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      'orderId': id,
      'updatedAt': _nowIso(),
      if (!current.containsKey('createdAt')) 'createdAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'Admin/Admin/orders',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<Map<String, dynamic>> createAdminOrder({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final id = _optionalString(payload, 'orderId') ??
        _optionalString(payload, 'id') ??
        _nextId('admin_order');
    final merged = await upsertAdminOrder(
      idToken: idToken,
      orderId: id,
      payload: payload,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<void> deleteAdminOrder({
    required String idToken,
    required String orderId,
  }) async {
    await _resolveUid(idToken);
    final id = orderId.trim();
    if (id.isEmpty) throw ApiException.badRequest('orderId is required.');
    await _firestoreClient.deleteDocument(
      collectionPath: 'Admin/Admin/orders',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> listShopCategoryProducts({
    required String idToken,
    required String shop,
    required String category,
  }) async {
    await _resolveUid(idToken);
    final shopName = shop.trim();
    final categoryName = category.trim();
    if (shopName.isEmpty || categoryName.isEmpty) {
      throw ApiException.badRequest('shop and category are required.');
    }
    final docs = await _firestoreClient.listDocuments(
      collectionPath: 'legacyProducts/$shopName/$categoryName',
      idToken: idToken,
      pageSize: 1000,
      orderBy: 'updatedAt desc',
    );
    final out = <String, dynamic>{};
    for (final doc in docs) {
      final id = '${doc['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final entry = <String, dynamic>{...doc}..remove('id');
      out[id] = entry;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getShopCategoryProduct({
    required String idToken,
    required String shop,
    required String category,
    required String productId,
  }) async {
    await _resolveUid(idToken);
    final shopName = shop.trim();
    final categoryName = category.trim();
    final id = productId.trim();
    if (shopName.isEmpty || categoryName.isEmpty || id.isEmpty) {
      throw ApiException.badRequest(
          'shop, category and productId are required.');
    }
    return _firestoreClient.getDocument(
      collectionPath: 'legacyProducts/$shopName/$categoryName',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> upsertShopCategoryProduct({
    required String idToken,
    required String shop,
    required String category,
    required String productId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final shopName = shop.trim();
    final categoryName = category.trim();
    final id = productId.trim();
    if (shopName.isEmpty || categoryName.isEmpty || id.isEmpty) {
      throw ApiException.badRequest(
          'shop, category and productId are required.');
    }
    final current = await _firestoreClient.getDocument(
          collectionPath: 'legacyProducts/$shopName/$categoryName',
          documentId: id,
          idToken: idToken,
        ) ??
        <String, dynamic>{};

    final imageUrl = await _uploadOne(
      idToken: idToken,
      folder: 'legacy_products/$shopName/$categoryName',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );

    final moreImages = _readStringList(current['imageUrlForMoreImages']);
    moreImages.addAll(_readStringList(payload['imageUrlForMoreImages']));
    if (imageUrl != null && imageUrl.isNotEmpty) {
      moreImages.add(imageUrl);
    }

    final merged = <String, dynamic>{
      ...current,
      ...payload,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'imageUrlForMoreImages': moreImages,
      'id': id,
      'title': payload['title'] ??
          payload['nameOfProduct'] ??
          current['title'] ??
          '',
      'category': categoryName,
      'shopName': shopName,
      'updatedAt': _nowIso(),
      if (!current.containsKey('createdAt')) 'createdAt': _nowIso(),
    };
    merged.remove('mediaBase64');
    merged.remove('fileName');
    merged.remove('contentType');

    await _firestoreClient.setDocument(
      collectionPath: 'legacyProducts/$shopName/$categoryName',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<Map<String, dynamic>> createShopCategoryProduct({
    required String idToken,
    required String shop,
    required String category,
    required Map<String, dynamic> payload,
  }) async {
    final id = _optionalString(payload, 'id') ??
        _optionalString(payload, 'productId') ??
        _nextId('prod');
    final merged = await upsertShopCategoryProduct(
      idToken: idToken,
      shop: shop,
      category: category,
      productId: id,
      payload: payload,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<void> deleteShopCategoryProduct({
    required String idToken,
    required String shop,
    required String category,
    required String productId,
  }) async {
    await _resolveUid(idToken);
    final shopName = shop.trim();
    final categoryName = category.trim();
    final id = productId.trim();
    if (shopName.isEmpty || categoryName.isEmpty || id.isEmpty) {
      throw ApiException.badRequest(
          'shop, category and productId are required.');
    }
    await _firestoreClient.deleteDocument(
      collectionPath: 'legacyProducts/$shopName/$categoryName',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> getUserFavorites({
    required String idToken,
    required String uid,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    if (userId.isEmpty) throw ApiException.badRequest('uid is required.');
    final docs = await _firestoreClient.listDocuments(
      collectionPath: 'userFavorites/$userId/items',
      idToken: idToken,
      pageSize: 1000,
      orderBy: 'updatedAt desc',
    );
    final out = <String, dynamic>{};
    for (final doc in docs) {
      final id = '${doc['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final entry = <String, dynamic>{...doc}..remove('id');
      out[id] = entry;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getUserFavorite({
    required String idToken,
    required String uid,
    required String productId,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = productId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and productId are required.');
    }
    return _firestoreClient.getDocument(
      collectionPath: 'userFavorites/$userId/items',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> upsertUserFavorite({
    required String idToken,
    required String uid,
    required String productId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = productId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and productId are required.');
    }
    final current = await _firestoreClient.getDocument(
          collectionPath: 'userFavorites/$userId/items',
          documentId: id,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      'id': id,
      'isFavorite': payload['isFavorite'] ?? true,
      'updatedAt': _nowIso(),
      if (!current.containsKey('createdAt')) 'createdAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'userFavorites/$userId/items',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<void> deleteUserFavorite({
    required String idToken,
    required String uid,
    required String productId,
  }) async {
    await _resolveUid(idToken);
    final userId = uid.trim();
    final id = productId.trim();
    if (userId.isEmpty || id.isEmpty) {
      throw ApiException.badRequest('uid and productId are required.');
    }
    await _firestoreClient.deleteDocument(
      collectionPath: 'userFavorites/$userId/items',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> listNews({
    required String idToken,
    int limit = 50,
    String? pageToken,
    String? screen,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'news',
      idToken: idToken,
      pageSize: limit.clamp(1, 500).toInt(),
      orderBy: 'created_at desc',
      pageToken: pageToken,
    );
    final items = <Map<String, dynamic>>[];
    for (final item in page.documents) {
      if (screen != null &&
          screen.trim().isNotEmpty &&
          '${item['screen'] ?? ''}'.trim() != screen.trim()) {
        continue;
      }
      items.add(item);
    }
    return <String, dynamic>{
      'items': items,
      'count': items.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createNews({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = _optionalString(payload, 'id') ?? _nextId('news');
    final mediaUrl = await _uploadOne(
      idToken: idToken,
      folder: 'news',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final now = _nowIso();
    final data = <String, dynamic>{
      ...payload,
      'id': id,
      'url': mediaUrl ?? payload['url'] ?? '',
      'created_at': payload['created_at'] ?? now,
      'updatedAt': now,
    };
    data.remove('mediaBase64');
    data.remove('fileName');
    data.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: 'news',
      documentId: id,
      idToken: idToken,
      data: data,
    );
    return data;
  }

  Future<Map<String, dynamic>?> getNews({
    required String idToken,
    required String newsId,
  }) async {
    await _resolveUid(idToken);
    final id = newsId.trim();
    if (id.isEmpty) throw ApiException.badRequest('newsId is required.');
    return _firestoreClient.getDocument(
      collectionPath: 'news',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> updateNews({
    required String idToken,
    required String newsId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = newsId.trim();
    if (id.isEmpty) throw ApiException.badRequest('newsId is required.');
    final current = await _firestoreClient.getDocument(
      collectionPath: 'news',
      documentId: id,
      idToken: idToken,
    );
    if (current == null) throw ApiException.notFound('News not found.');
    final mediaUrl = await _uploadOne(
      idToken: idToken,
      folder: 'news',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      if (mediaUrl != null) 'url': mediaUrl,
      'updatedAt': _nowIso(),
    };
    merged.remove('mediaBase64');
    merged.remove('fileName');
    merged.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: 'news',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<void> deleteNews({
    required String idToken,
    required String newsId,
  }) async {
    await _resolveUid(idToken);
    final id = newsId.trim();
    if (id.isEmpty) throw ApiException.badRequest('newsId is required.');
    await _firestoreClient.deleteDocument(
      collectionPath: 'news',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> listLegacyPromos({
    required String idToken,
    required String collectionPath,
    int limit = 80,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: collectionPath,
      idToken: idToken,
      pageSize: limit.clamp(1, 500).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );
    return <String, dynamic>{
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createLegacyPromo({
    required String idToken,
    required String collectionPath,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = _optionalString(payload, 'id') ?? _nextId('promo');
    final mediaUrl = await _uploadOne(
      idToken: idToken,
      folder: 'promo',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final now = _nowIso();
    final data = <String, dynamic>{
      ...payload,
      'id': id,
      'imageUrl': mediaUrl ?? payload['imageUrl'] ?? '',
      'timestamp': payload['timestamp'] ?? now,
      'updatedAt': now,
    };
    data.remove('mediaBase64');
    data.remove('fileName');
    data.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: collectionPath,
      documentId: id,
      idToken: idToken,
      data: data,
    );
    return data;
  }

  Future<Map<String, dynamic>?> getLegacyPromo({
    required String idToken,
    required String collectionPath,
    required String promoId,
  }) async {
    await _resolveUid(idToken);
    final id = promoId.trim();
    if (id.isEmpty) throw ApiException.badRequest('promoId is required.');
    return _firestoreClient.getDocument(
      collectionPath: collectionPath,
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> updateLegacyPromo({
    required String idToken,
    required String collectionPath,
    required String promoId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = promoId.trim();
    if (id.isEmpty) throw ApiException.badRequest('promoId is required.');
    final current = await _firestoreClient.getDocument(
      collectionPath: collectionPath,
      documentId: id,
      idToken: idToken,
    );
    if (current == null) throw ApiException.notFound('Promo not found.');
    final mediaUrl = await _uploadOne(
      idToken: idToken,
      folder: 'promo',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      if (mediaUrl != null) 'imageUrl': mediaUrl,
      'updatedAt': _nowIso(),
    };
    merged.remove('mediaBase64');
    merged.remove('fileName');
    merged.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: collectionPath,
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<void> deleteLegacyPromo({
    required String idToken,
    required String collectionPath,
    required String promoId,
  }) async {
    await _resolveUid(idToken);
    final id = promoId.trim();
    if (id.isEmpty) throw ApiException.badRequest('promoId is required.');
    await _firestoreClient.deleteDocument(
      collectionPath: collectionPath,
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> getVersionInfo({
    required String idToken,
  }) async {
    await _resolveUid(idToken);
    final info = await _firestoreClient.getDocument(
      collectionPath: 'appConfig',
      documentId: 'versionInfo',
      idToken: idToken,
    );
    return info ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> upsertVersionInfo({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final current = await _firestoreClient.getDocument(
          collectionPath: 'appConfig',
          documentId: 'versionInfo',
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      'updatedAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'appConfig',
      documentId: 'versionInfo',
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<Map<String, dynamic>> listAppMessages({
    required String idToken,
    int limit = 40,
    String? pageToken,
  }) async {
    await _resolveUid(idToken);
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'appMessages',
      idToken: idToken,
      pageSize: limit.clamp(1, 300).toInt(),
      orderBy: 'created_at desc',
      pageToken: pageToken,
    );
    return <String, dynamic>{
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createAppMessage({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = _optionalString(payload, 'id') ?? _nextId('msg');
    final imageUrl = await _uploadOne(
      idToken: idToken,
      folder: 'app_messages',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final now = _nowIso();
    final data = <String, dynamic>{
      ...payload,
      'id': id,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'created_at': payload['created_at'] ?? now,
      'updatedAt': now,
    };
    data.remove('mediaBase64');
    data.remove('fileName');
    data.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: 'appMessages',
      documentId: id,
      idToken: idToken,
      data: data,
    );
    return data;
  }

  Future<Map<String, dynamic>?> getAppMessage({
    required String idToken,
    required String messageId,
  }) async {
    await _resolveUid(idToken);
    final id = messageId.trim();
    if (id.isEmpty) throw ApiException.badRequest('messageId is required.');
    return _firestoreClient.getDocument(
      collectionPath: 'appMessages',
      documentId: id,
      idToken: idToken,
    );
  }

  Future<Map<String, dynamic>> updateAppMessage({
    required String idToken,
    required String messageId,
    required Map<String, dynamic> payload,
  }) async {
    await _resolveUid(idToken);
    final id = messageId.trim();
    if (id.isEmpty) throw ApiException.badRequest('messageId is required.');
    final current = await _firestoreClient.getDocument(
      collectionPath: 'appMessages',
      documentId: id,
      idToken: idToken,
    );
    if (current == null) throw ApiException.notFound('App message not found.');
    final imageUrl = await _uploadOne(
      idToken: idToken,
      folder: 'app_messages',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      fileName: _optionalString(payload, 'fileName'),
      contentType: _optionalString(payload, 'contentType'),
    );
    final merged = <String, dynamic>{
      ...current,
      ...payload,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'updatedAt': _nowIso(),
    };
    merged.remove('mediaBase64');
    merged.remove('fileName');
    merged.remove('contentType');
    await _firestoreClient.setDocument(
      collectionPath: 'appMessages',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<void> deleteAppMessage({
    required String idToken,
    required String messageId,
  }) async {
    await _resolveUid(idToken);
    final id = messageId.trim();
    if (id.isEmpty) throw ApiException.badRequest('messageId is required.');
    await _firestoreClient.deleteDocument(
      collectionPath: 'appMessages',
      documentId: id,
      idToken: idToken,
    );
  }
}
