import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';

final commerceService = CommerceService();

class CommerceService {
  CommerceService({
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
  }

  List<Map<String, dynamic>> _readListMap(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        out.add(Map<String, dynamic>.from(item));
      } else if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
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

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  bool? _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
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
  }) async {
    final raw = mediaBase64?.trim() ?? '';
    if (raw.isEmpty) return null;
    final upload = await _mediaService.uploadForPath(
      idToken: idToken,
      mediaBase64: raw,
      folder: folder,
      defaultNamePrefix: _nextId('file'),
    );
    return '${upload['downloadUrl'] ?? ''}';
  }

  Future<List<String>> _uploadMany({
    required String idToken,
    required String folder,
    String? mediaBase64,
    dynamic mediaBase64List,
  }) async {
    final out = <String>[];
    final single = mediaBase64?.trim() ?? '';
    if (single.isNotEmpty) {
      final upload = await _mediaService.uploadForPath(
        idToken: idToken,
        mediaBase64: single,
        folder: folder,
        defaultNamePrefix: _nextId('file'),
      );
      out.add('${upload['downloadUrl'] ?? ''}');
    }
    if (mediaBase64List is List) {
      var index = 0;
      for (final raw in mediaBase64List) {
        if (raw is! String || raw.trim().isEmpty) continue;
        final upload = await _mediaService.uploadForPath(
          idToken: idToken,
          mediaBase64: raw.trim(),
          folder: folder,
          defaultNamePrefix: '${_nextId('file')}_$index',
        );
        out.add('${upload['downloadUrl'] ?? ''}');
        index++;
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> listProducts({
    required String idToken,
    int limit = 30,
    String? pageToken,
    String? shopId,
    String? ownerId,
    String? category,
    String? search,
    bool? active,
    double? minPrice,
    double? maxPrice,
  }) async {
    await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 200).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'products',
      idToken: idToken,
      pageSize: max(safeLimit * 3, 80).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );

    final out = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      final itemShop = '${item['shopId'] ?? ''}'.trim();
      final itemOwner = '${item['ownerId'] ?? ''}'.trim();
      final itemCategory = '${item['category'] ?? ''}'.trim().toLowerCase();
      final itemName = '${item['name'] ?? ''}'.trim().toLowerCase();
      final itemDesc = '${item['description'] ?? ''}'.trim().toLowerCase();
      final itemPrice = _toDouble(item['price']) ?? 0.0;
      final isActive = _isTruthy(item['isActive']) ?? true;

      if (shopId != null &&
          shopId.trim().isNotEmpty &&
          itemShop != shopId.trim()) {
        continue;
      }
      if (ownerId != null &&
          ownerId.trim().isNotEmpty &&
          itemOwner != ownerId.trim()) {
        continue;
      }
      if (category != null &&
          category.trim().isNotEmpty &&
          !itemCategory.contains(category.trim().toLowerCase())) {
        continue;
      }
      if (search != null && search.trim().isNotEmpty) {
        final needle = search.trim().toLowerCase();
        if (!itemName.contains(needle) && !itemDesc.contains(needle)) continue;
      }
      if (active != null && isActive != active) continue;
      if (minPrice != null && itemPrice < minPrice) continue;
      if (maxPrice != null && itemPrice > maxPrice) continue;
      out.add(item);
      if (out.length >= safeLimit) break;
    }

    return <String, dynamic>{
      'items': out,
      'count': out.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createProduct({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final now = _nowIso();
    final productId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'productId') ??
        _nextId('product');
    final name = _requiredString(payload, 'name');

    final shopId = _optionalString(payload, 'shopId') ?? '';
    var ownerId = _optionalString(payload, 'ownerId') ?? uid;
    var shopName = _optionalString(payload, 'shopName') ?? '';
    if (shopId.isNotEmpty) {
      final shop = await _firestoreClient.getDocument(
        collectionPath: 'shops',
        documentId: shopId,
        idToken: idToken,
      );
      if (shop != null) {
        ownerId = '${shop['ownerId'] ?? ownerId}'.trim();
        shopName = '${shop['name'] ?? shopName}'.trim();
      }
    }
    if (ownerId != uid) {
      throw ApiException.forbidden('Only the owner can create this product.');
    }

    final uploaded = await _uploadMany(
      idToken: idToken,
      folder: 'products/$ownerId',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      mediaBase64List: payload['mediaBase64List'],
    );
    final imageUrls = <String>[
      ..._readStringList(payload['imageUrls']),
      ...uploaded,
    ];

    final data = <String, dynamic>{
      'id': productId,
      'productId': productId,
      'ownerId': ownerId,
      'shopId': shopId,
      'shopName': shopName,
      'name': name,
      'description': _optionalString(payload, 'description') ?? '',
      'category': _optionalString(payload, 'category') ?? '',
      'price': _toDouble(payload['price']) ?? 0.0,
      'compareAtPrice': _toDouble(payload['compareAtPrice']) ?? 0.0,
      'currency': _optionalString(payload, 'currency') ?? 'NGN',
      'stock': _toInt(payload['stock']) ?? 0,
      'unit': _optionalString(payload, 'unit') ?? '',
      'isActive': _isTruthy(payload['isActive']) ?? true,
      'isFeatured': _isTruthy(payload['isFeatured']) ?? false,
      'tags': _readStringList(payload['tags']),
      'imageUrls': imageUrls,
      'createdAt': now,
      'updatedAt': now,
      'timestamp': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'products',
      documentId: productId,
      idToken: idToken,
      data: data,
    );
    if (shopId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'shops/$shopId/products',
        documentId: productId,
        idToken: idToken,
        data: data,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> getProduct({
    required String idToken,
    required String productId,
  }) async {
    await _resolveUid(idToken);
    final id = productId.trim();
    if (id.isEmpty) throw ApiException.badRequest('product_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'products',
      documentId: id,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Product not found.');
    return <String, dynamic>{'id': id, ...doc};
  }

  Future<Map<String, dynamic>> updateProduct({
    required String idToken,
    required String productId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getProduct(idToken: idToken, productId: productId);
    await _assertProductOwner(idToken: idToken, uid: uid, product: current);

    final uploads = await _uploadMany(
      idToken: idToken,
      folder: 'products/$uid',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
      mediaBase64List: payload['mediaBase64List'],
    );

    final replaceImages = _isTruthy(payload['replaceImages']) == true;
    final baseImages =
        replaceImages ? <String>[] : _readStringList(current['imageUrls']);
    final mergedImages = <String>[
      ...baseImages,
      ..._readStringList(payload['imageUrls']),
      ...uploads,
    ];

    final merged = <String, dynamic>{
      ...current,
      ..._safeProductUpdate(payload),
      'imageUrls': mergedImages,
      'updatedAt': _nowIso(),
    };
    final id = productId.trim();
    await _firestoreClient.setDocument(
      collectionPath: 'products',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    final shopId = '${merged['shopId'] ?? ''}'.trim();
    if (shopId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'shops/$shopId/products',
        documentId: id,
        idToken: idToken,
        data: merged,
      );
    }
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> deleteProduct({
    required String idToken,
    required String productId,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getProduct(idToken: idToken, productId: productId);
    await _assertProductOwner(idToken: idToken, uid: uid, product: current);

    final id = productId.trim();
    await _firestoreClient.deleteDocument(
      collectionPath: 'products',
      documentId: id,
      idToken: idToken,
    );
    final shopId = '${current['shopId'] ?? ''}'.trim();
    if (shopId.isNotEmpty) {
      await _firestoreClient.deleteDocument(
        collectionPath: 'shops/$shopId/products',
        documentId: id,
        idToken: idToken,
      );
    }
    return <String, dynamic>{'deleted': true, 'productId': id};
  }

  Future<void> _assertProductOwner({
    required String idToken,
    required String uid,
    required Map<String, dynamic> product,
  }) async {
    final ownerId = '${product['ownerId'] ?? ''}'.trim();
    if (ownerId == uid) return;
    final shopId = '${product['shopId'] ?? ''}'.trim();
    if (shopId.isEmpty) {
      throw ApiException.forbidden('Only the owner can modify this product.');
    }
    final shop = await _firestoreClient.getDocument(
      collectionPath: 'shops',
      documentId: shopId,
      idToken: idToken,
    );
    if ('${shop?['ownerId'] ?? ''}'.trim() != uid) {
      throw ApiException.forbidden('Only the owner can modify this product.');
    }
  }

  Map<String, dynamic> _safeProductUpdate(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'productId',
      'ownerId',
      'shopId',
      'createdAt',
      'timestamp',
      'mediaBase64',
      'mediaBase64List',
      'replaceImages',
    };
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> listShops({
    required String idToken,
    int limit = 30,
    String? pageToken,
    String? ownerId,
    String? zoneId,
    String? search,
    bool? verified,
    bool? open,
  }) async {
    await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 200).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'shops',
      idToken: idToken,
      pageSize: max(safeLimit * 3, 80).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );

    final out = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      final itemOwner = '${item['ownerId'] ?? ''}'.trim();
      final itemZone = '${item['zoneId'] ?? ''}'.trim();
      final itemName = '${item['name'] ?? ''}'.trim().toLowerCase();
      final itemDesc = '${item['description'] ?? ''}'.trim().toLowerCase();
      final itemVerified = _isTruthy(item['isVerified']) ?? false;
      final itemOpen = _isTruthy(item['isOpen']) ?? true;

      if (ownerId != null &&
          ownerId.trim().isNotEmpty &&
          itemOwner != ownerId.trim()) {
        continue;
      }
      if (zoneId != null &&
          zoneId.trim().isNotEmpty &&
          itemZone != zoneId.trim()) {
        continue;
      }
      if (search != null && search.trim().isNotEmpty) {
        final needle = search.trim().toLowerCase();
        if (!itemName.contains(needle) && !itemDesc.contains(needle)) continue;
      }
      if (verified != null && itemVerified != verified) continue;
      if (open != null && itemOpen != open) continue;
      out.add(item);
      if (out.length >= safeLimit) break;
    }

    return <String, dynamic>{
      'items': out,
      'count': out.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createShop({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final ownerId = _optionalString(payload, 'ownerId') ?? uid;
    if (ownerId != uid) {
      throw ApiException.forbidden('Only the owner can create this shop.');
    }

    final shopId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'shopId') ??
        _nextId('shop');
    final name = _requiredString(payload, 'name');
    final now = _nowIso();

    final logoUpload = await _uploadOne(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64: _optionalString(payload, 'logoBase64'),
    );
    final coverUpload = await _uploadOne(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64: _optionalString(payload, 'coverBase64'),
    );
    final galleryUploads = await _uploadMany(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64List: payload['mediaBase64List'],
    );

    final data = <String, dynamic>{
      'id': shopId,
      'shopId': shopId,
      'ownerId': ownerId,
      'name': name,
      'description': _optionalString(payload, 'description') ?? '',
      'zoneId': _optionalString(payload, 'zoneId') ?? '',
      'address': _optionalString(payload, 'address') ?? '',
      'phone': _optionalString(payload, 'phone') ?? '',
      'email': _optionalString(payload, 'email') ?? '',
      'logoUrl': logoUpload ?? _optionalString(payload, 'logoUrl') ?? '',
      'coverUrl': coverUpload ?? _optionalString(payload, 'coverUrl') ?? '',
      'galleryUrls': <String>[
        ..._readStringList(payload['galleryUrls']),
        ...galleryUploads,
      ],
      'isOpen': _isTruthy(payload['isOpen']) ?? true,
      'isVerified': _isTruthy(payload['isVerified']) ?? false,
      'status': _optionalString(payload, 'status') ?? 'active',
      'lat': _toDouble(payload['lat']) ?? 0.0,
      'lng': _toDouble(payload['lng']) ?? 0.0,
      'categories': _readStringList(payload['categories']),
      'createdAt': now,
      'updatedAt': now,
      'timestamp': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'shops',
      documentId: shopId,
      idToken: idToken,
      data: data,
    );
    await _upsertShopOwnerList(
      idToken: idToken,
      ownerId: ownerId,
      shopId: shopId,
      shopName: name,
      payload: payload,
    );
    return data;
  }

  Future<Map<String, dynamic>> getShop({
    required String idToken,
    required String shopId,
  }) async {
    await _resolveUid(idToken);
    final id = shopId.trim();
    if (id.isEmpty) throw ApiException.badRequest('shop_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'shops',
      documentId: id,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Shop not found.');
    return <String, dynamic>{'id': id, ...doc};
  }

  Future<Map<String, dynamic>> updateShop({
    required String idToken,
    required String shopId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getShop(idToken: idToken, shopId: shopId);
    final ownerId = '${current['ownerId'] ?? ''}'.trim();
    if (ownerId != uid) {
      throw ApiException.forbidden('Only the owner can update this shop.');
    }

    final logoUpload = await _uploadOne(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64: _optionalString(payload, 'logoBase64'),
    );
    final coverUpload = await _uploadOne(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64: _optionalString(payload, 'coverBase64'),
    );
    final galleryUploads = await _uploadMany(
      idToken: idToken,
      folder: 'shops/$ownerId',
      mediaBase64List: payload['mediaBase64List'],
    );
    final replaceGallery = _isTruthy(payload['replaceGallery']) == true;
    final currentGallery =
        replaceGallery ? <String>[] : _readStringList(current['galleryUrls']);
    final merged = <String, dynamic>{
      ...current,
      ..._safeShopUpdate(payload),
      if (logoUpload != null) 'logoUrl': logoUpload,
      if (coverUpload != null) 'coverUrl': coverUpload,
      'galleryUrls': <String>[
        ...currentGallery,
        ..._readStringList(payload['galleryUrls']),
        ...galleryUploads,
      ],
      'updatedAt': _nowIso(),
    };
    final id = shopId.trim();
    await _firestoreClient.setDocument(
      collectionPath: 'shops',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    await _upsertShopOwnerList(
      idToken: idToken,
      ownerId: ownerId,
      shopId: id,
      shopName: '${merged['name'] ?? ''}',
      payload: merged,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> deleteShop({
    required String idToken,
    required String shopId,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getShop(idToken: idToken, shopId: shopId);
    final ownerId = '${current['ownerId'] ?? ''}'.trim();
    if (ownerId != uid) {
      throw ApiException.forbidden('Only the owner can delete this shop.');
    }
    final id = shopId.trim();
    await _firestoreClient.deleteDocument(
      collectionPath: 'shops',
      documentId: id,
      idToken: idToken,
    );
    await _removeOwnerShop(idToken: idToken, ownerId: ownerId, shopId: id);
    return <String, dynamic>{'deleted': true, 'shopId': id};
  }

  Map<String, dynamic> _safeShopUpdate(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'shopId',
      'ownerId',
      'createdAt',
      'timestamp',
      'logoBase64',
      'coverBase64',
      'mediaBase64List',
      'replaceGallery',
      'ownerName',
    };
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> listZones({
    required String idToken,
    int limit = 50,
    String? pageToken,
    String? country,
    String? state,
    String? city,
    String? search,
    bool? active,
  }) async {
    await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 300).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'zones',
      idToken: idToken,
      pageSize: max(safeLimit * 2, 80).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );
    final out = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      if (country != null &&
          country.trim().isNotEmpty &&
          '${item['country'] ?? ''}'.trim().toLowerCase() !=
              country.trim().toLowerCase()) {
        continue;
      }
      if (state != null &&
          state.trim().isNotEmpty &&
          '${item['state'] ?? ''}'.trim().toLowerCase() !=
              state.trim().toLowerCase()) {
        continue;
      }
      if (city != null &&
          city.trim().isNotEmpty &&
          '${item['city'] ?? ''}'.trim().toLowerCase() !=
              city.trim().toLowerCase()) {
        continue;
      }
      if (active != null && (_isTruthy(item['isActive']) ?? true) != active) {
        continue;
      }
      if (search != null && search.trim().isNotEmpty) {
        final needle = search.trim().toLowerCase();
        final haystack = <String>[
          '${item['name'] ?? ''}',
          '${item['city'] ?? ''}',
          '${item['state'] ?? ''}',
          '${item['country'] ?? ''}',
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) continue;
      }
      out.add(item);
      if (out.length >= safeLimit) break;
    }
    return <String, dynamic>{
      'items': out,
      'count': out.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createZone({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final zoneId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'zoneId') ??
        _nextId('zone');
    final name = _requiredString(payload, 'name');
    final now = _nowIso();

    final zone = <String, dynamic>{
      'id': zoneId,
      'zoneId': zoneId,
      'name': name,
      'city': _optionalString(payload, 'city') ?? '',
      'state': _optionalString(payload, 'state') ?? '',
      'country': _optionalString(payload, 'country') ?? '',
      'deliveryFee': _toDouble(payload['deliveryFee']) ?? 0.0,
      'isActive': _isTruthy(payload['isActive']) ?? true,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
      'timestamp': now,
    };
    await _firestoreClient.setDocument(
      collectionPath: 'zones',
      documentId: zoneId,
      idToken: idToken,
      data: zone,
    );
    return zone;
  }

  Future<Map<String, dynamic>> getZone({
    required String idToken,
    required String zoneId,
  }) async {
    await _resolveUid(idToken);
    final id = zoneId.trim();
    if (id.isEmpty) throw ApiException.badRequest('zone_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'zones',
      documentId: id,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Zone not found.');
    return <String, dynamic>{'id': id, ...doc};
  }

  Future<Map<String, dynamic>> updateZone({
    required String idToken,
    required String zoneId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getZone(idToken: idToken, zoneId: zoneId);
    final createdBy = '${current['createdBy'] ?? ''}'.trim();
    if (createdBy.isNotEmpty && createdBy != uid) {
      throw ApiException.forbidden('Only the creator can update this zone.');
    }
    final merged = <String, dynamic>{
      ...current,
      ..._safeZoneUpdate(payload),
      'updatedAt': _nowIso(),
    };
    final id = zoneId.trim();
    await _firestoreClient.setDocument(
      collectionPath: 'zones',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> deleteZone({
    required String idToken,
    required String zoneId,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getZone(idToken: idToken, zoneId: zoneId);
    final createdBy = '${current['createdBy'] ?? ''}'.trim();
    if (createdBy.isNotEmpty && createdBy != uid) {
      throw ApiException.forbidden('Only the creator can delete this zone.');
    }
    final id = zoneId.trim();
    await _firestoreClient.deleteDocument(
      collectionPath: 'zones',
      documentId: id,
      idToken: idToken,
    );
    return <String, dynamic>{'deleted': true, 'zoneId': id};
  }

  Map<String, dynamic> _safeZoneUpdate(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'zoneId',
      'createdAt',
      'timestamp',
      'createdBy'
    };
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> listShopOwners({
    required String idToken,
    int limit = 50,
    String? pageToken,
    String? zoneId,
    String? search,
    bool? verified,
  }) async {
    await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 300).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'shopOwnersList',
      idToken: idToken,
      pageSize: max(safeLimit * 2, 80).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );
    final out = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      if (zoneId != null &&
          zoneId.trim().isNotEmpty &&
          '${item['zoneId'] ?? ''}'.trim() != zoneId.trim()) {
        continue;
      }
      if (verified != null &&
          (_isTruthy(item['isVerified']) ?? false) != verified) {
        continue;
      }
      if (search != null && search.trim().isNotEmpty) {
        final needle = search.trim().toLowerCase();
        final haystack = <String>[
          '${item['name'] ?? ''}',
          '${item['email'] ?? ''}',
          '${item['phone'] ?? ''}',
          '${item['shopName'] ?? ''}',
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) continue;
      }
      out.add(item);
      if (out.length >= safeLimit) break;
    }
    return <String, dynamic>{
      'items': out,
      'count': out.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> getShopOwner({
    required String idToken,
    required String ownerId,
  }) async {
    await _resolveUid(idToken);
    final id = ownerId.trim();
    if (id.isEmpty) throw ApiException.badRequest('owner_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'shopOwnersList',
      documentId: id,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Shop owner not found.');
    return <String, dynamic>{'id': id, ...doc};
  }

  Future<Map<String, dynamic>> upsertShopOwner({
    required String idToken,
    required String ownerId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final id = ownerId.trim();
    if (id.isEmpty) throw ApiException.badRequest('owner_id is required.');
    if (id != uid) {
      throw ApiException.forbidden(
          'You can only update your own owner profile.');
    }
    final current = await _firestoreClient.getDocument(
      collectionPath: 'shopOwnersList',
      documentId: id,
      idToken: idToken,
    );
    final now = _nowIso();
    final merged = <String, dynamic>{
      ...?current,
      ..._safeShopOwnerUpdate(payload),
      'ownerId': id,
      'updatedAt': now,
      if (current == null) 'createdAt': now,
    };
    await _firestoreClient.setDocument(
      collectionPath: 'shopOwnersList',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<void> _upsertShopOwnerList({
    required String idToken,
    required String ownerId,
    required String shopId,
    required String shopName,
    required Map<String, dynamic> payload,
  }) async {
    final current = await _firestoreClient.getDocument(
      collectionPath: 'shopOwnersList',
      documentId: ownerId,
      idToken: idToken,
    );
    final shopIds = _readStringList(current?['shopIds']);
    if (!shopIds.contains(shopId)) shopIds.add(shopId);
    final now = _nowIso();
    await _firestoreClient.setDocument(
      collectionPath: 'shopOwnersList',
      documentId: ownerId,
      idToken: idToken,
      data: <String, dynamic>{
        ...?current,
        'ownerId': ownerId,
        'name': _optionalString(payload, 'ownerName') ??
            _optionalString(payload, 'name') ??
            current?['name'] ??
            '',
        'email': _optionalString(payload, 'email') ?? current?['email'] ?? '',
        'phone': _optionalString(payload, 'phone') ?? current?['phone'] ?? '',
        'zoneId':
            _optionalString(payload, 'zoneId') ?? current?['zoneId'] ?? '',
        'shopName': shopName,
        'shopIds': shopIds,
        'totalShops': shopIds.length,
        'isVerified': _isTruthy(payload['isVerified']) ??
            _isTruthy(current?['isVerified']) ??
            false,
        'updatedAt': now,
        if (current == null) 'createdAt': now,
      },
    );
  }

  Future<void> _removeOwnerShop({
    required String idToken,
    required String ownerId,
    required String shopId,
  }) async {
    final current = await _firestoreClient.getDocument(
      collectionPath: 'shopOwnersList',
      documentId: ownerId,
      idToken: idToken,
    );
    if (current == null) return;
    final shopIds = _readStringList(current['shopIds'])
      ..removeWhere((id) => id == shopId);
    await _firestoreClient.setDocument(
      collectionPath: 'shopOwnersList',
      documentId: ownerId,
      idToken: idToken,
      data: <String, dynamic>{
        ...current,
        'shopIds': shopIds,
        'totalShops': shopIds.length,
        'updatedAt': _nowIso(),
      },
    );
  }

  Map<String, dynamic> _safeShopOwnerUpdate(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'ownerId',
      'createdAt',
      'timestamp',
      'shopIds',
      'totalShops',
    };
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> listOrders({
    required String idToken,
    int limit = 40,
    String? pageToken,
    bool mine = true,
    String? buyerId,
    String? sellerId,
    String? shopId,
    String? status,
    String? paymentStatus,
  }) async {
    final uid = await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 200).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'orders',
      idToken: idToken,
      pageSize: max(safeLimit * 3, 90).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );
    final out = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      final itemBuyer = '${item['buyerId'] ?? ''}'.trim();
      final itemSeller = '${item['sellerId'] ?? ''}'.trim();
      final itemShop = '${item['shopId'] ?? ''}'.trim();
      final itemStatus = '${item['status'] ?? ''}'.trim().toLowerCase();
      final itemPayStatus =
          '${item['paymentStatus'] ?? ''}'.trim().toLowerCase();

      if (mine && itemBuyer != uid && itemSeller != uid) continue;
      if (buyerId != null &&
          buyerId.trim().isNotEmpty &&
          itemBuyer != buyerId.trim()) {
        continue;
      }
      if (sellerId != null &&
          sellerId.trim().isNotEmpty &&
          itemSeller != sellerId.trim()) {
        continue;
      }
      if (shopId != null &&
          shopId.trim().isNotEmpty &&
          itemShop != shopId.trim()) {
        continue;
      }
      if (status != null &&
          status.trim().isNotEmpty &&
          itemStatus != status.trim().toLowerCase()) {
        continue;
      }
      if (paymentStatus != null &&
          paymentStatus.trim().isNotEmpty &&
          itemPayStatus != paymentStatus.trim().toLowerCase()) {
        continue;
      }
      out.add(item);
      if (out.length >= safeLimit) break;
    }
    return <String, dynamic>{
      'items': out,
      'count': out.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createOrder({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final now = _nowIso();
    final orderId = _optionalString(payload, 'id') ??
        _optionalString(payload, 'orderId') ??
        _nextId('order');
    final buyerId = _optionalString(payload, 'buyerId') ?? uid;
    if (buyerId != uid) {
      throw ApiException.forbidden('Only the buyer can create this order.');
    }

    final items = _readListMap(payload['items']);
    if (items.isEmpty) throw ApiException.badRequest('items is required.');
    final shopId = _optionalString(payload, 'shopId') ?? '';

    var sellerId = _optionalString(payload, 'sellerId') ?? '';
    if (shopId.isNotEmpty) {
      final shop = await _firestoreClient.getDocument(
        collectionPath: 'shops',
        documentId: shopId,
        idToken: idToken,
      );
      if (shop != null) {
        sellerId = '${shop['ownerId'] ?? sellerId}'.trim();
      }
    }

    final subtotal =
        _toDouble(payload['subtotal']) ?? _sumOrderItems(items, 'price');
    final deliveryFee = _toDouble(payload['deliveryFee']) ?? 0.0;
    final serviceFee = _toDouble(payload['serviceFee']) ?? 0.0;
    final discount = _toDouble(payload['discount']) ?? 0.0;
    final total = _toDouble(payload['total']) ??
        (subtotal + deliveryFee + serviceFee - discount);

    final proofUpload = await _uploadOne(
      idToken: idToken,
      folder: 'orders/$buyerId',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
    );
    final attachments = <String>[
      ..._readStringList(payload['attachments']),
      if (proofUpload != null) proofUpload,
    ];

    final order = <String, dynamic>{
      'id': orderId,
      'orderId': orderId,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'shopId': shopId,
      'items': items,
      'currency': _optionalString(payload, 'currency') ?? 'NGN',
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'serviceFee': serviceFee,
      'discount': discount,
      'total': total,
      'paymentMethod': _optionalString(payload, 'paymentMethod') ?? '',
      'paymentStatus':
          _optionalString(payload, 'paymentStatus') ?? 'pending_payment',
      'status': _optionalString(payload, 'status') ?? 'pending',
      'deliveryAddress': _optionalString(payload, 'deliveryAddress') ?? '',
      'note': _optionalString(payload, 'note') ?? '',
      'attachments': attachments,
      'createdAt': now,
      'updatedAt': now,
      'timestamp': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'orders',
      documentId: orderId,
      idToken: idToken,
      data: order,
    );
    if (shopId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'shops/$shopId/orders',
        documentId: orderId,
        idToken: idToken,
        data: order,
      );
    }
    return order;
  }

  Future<Map<String, dynamic>> getOrder({
    required String idToken,
    required String orderId,
  }) async {
    final uid = await _resolveUid(idToken);
    final id = orderId.trim();
    if (id.isEmpty) throw ApiException.badRequest('order_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'orders',
      documentId: id,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Order not found.');
    final order = <String, dynamic>{'id': id, ...doc};
    await _assertOrderAccess(idToken: idToken, uid: uid, order: order);
    return order;
  }

  Future<Map<String, dynamic>> updateOrder({
    required String idToken,
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getOrder(idToken: idToken, orderId: orderId);
    await _assertOrderAccess(idToken: idToken, uid: uid, order: current);

    final upload = await _uploadOne(
      idToken: idToken,
      folder: 'orders/$uid',
      mediaBase64: _optionalString(payload, 'mediaBase64'),
    );
    final merged = <String, dynamic>{
      ...current,
      ..._safeOrderUpdate(payload),
      'attachments': <String>[
        ..._readStringList(current['attachments']),
        ..._readStringList(payload['attachments']),
        if (upload != null) upload,
      ],
      'updatedAt': _nowIso(),
    };
    final id = orderId.trim();
    await _firestoreClient.setDocument(
      collectionPath: 'orders',
      documentId: id,
      idToken: idToken,
      data: merged,
    );
    final shopId = '${merged['shopId'] ?? ''}'.trim();
    if (shopId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'shops/$shopId/orders',
        documentId: id,
        idToken: idToken,
        data: merged,
      );
    }
    return <String, dynamic>{'id': id, ...merged};
  }

  Future<Map<String, dynamic>> deleteOrder({
    required String idToken,
    required String orderId,
  }) async {
    final uid = await _resolveUid(idToken);
    final current = await getOrder(idToken: idToken, orderId: orderId);
    await _assertOrderAccess(idToken: idToken, uid: uid, order: current);

    final id = orderId.trim();
    await _firestoreClient.deleteDocument(
      collectionPath: 'orders',
      documentId: id,
      idToken: idToken,
    );
    final shopId = '${current['shopId'] ?? ''}'.trim();
    if (shopId.isNotEmpty) {
      await _firestoreClient.deleteDocument(
        collectionPath: 'shops/$shopId/orders',
        documentId: id,
        idToken: idToken,
      );
    }
    return <String, dynamic>{'deleted': true, 'orderId': id};
  }

  Future<void> _assertOrderAccess({
    required String idToken,
    required String uid,
    required Map<String, dynamic> order,
  }) async {
    final buyerId = '${order['buyerId'] ?? ''}'.trim();
    final sellerId = '${order['sellerId'] ?? ''}'.trim();
    if (buyerId == uid || sellerId == uid) return;
    final shopId = '${order['shopId'] ?? ''}'.trim();
    if (shopId.isEmpty) {
      throw ApiException.forbidden('You do not have access to this order.');
    }
    final shop = await _firestoreClient.getDocument(
      collectionPath: 'shops',
      documentId: shopId,
      idToken: idToken,
    );
    if ('${shop?['ownerId'] ?? ''}'.trim() != uid) {
      throw ApiException.forbidden('You do not have access to this order.');
    }
  }

  double _sumOrderItems(List<Map<String, dynamic>> items, String priceKey) {
    var total = 0.0;
    for (final item in items) {
      final price = _toDouble(item[priceKey]) ?? 0.0;
      final qty = _toInt(item['quantity']) ?? 1;
      total += price * qty;
    }
    return total;
  }

  Map<String, dynamic> _safeOrderUpdate(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'orderId',
      'buyerId',
      'sellerId',
      'shopId',
      'createdAt',
      'timestamp',
      'mediaBase64',
    };
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }
}
