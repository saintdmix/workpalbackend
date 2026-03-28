import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final relationshipService = RelationshipService();

class RelationshipService {
  RelationshipService({
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

  Future<Map<String, dynamic>> getVendorRelationship({
    required String idToken,
    required String vendorId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final vendor =
        await _getVendorOrThrow(idToken: idToken, vendorId: vendorId);
    final followerIds = _readStringList(vendor.data['followerIds']);
    final followingIds = _readStringList(actor.profile['followingIds']);
    final isFollowing =
        followerIds.contains(actor.uid) || followingIds.contains(vendor.id);

    return <String, dynamic>{
      'vendorId': vendor.id,
      'isFollowing': isFollowing,
      'followers': followerIds.length,
      'followerIds': followerIds,
      'followingIds': followingIds,
    };
  }

  Future<Map<String, dynamic>> setVendorFollow({
    required String idToken,
    required String vendorId,
    bool? follow,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final vendor =
        await _getVendorOrThrow(idToken: idToken, vendorId: vendorId);

    if (actor.uid == vendor.id) {
      throw ApiException.badRequest('You cannot follow yourself.');
    }

    final followerIds = _readStringList(vendor.data['followerIds']);
    final currentlyFollowing = followerIds.contains(actor.uid);
    final shouldFollow = follow ?? !currentlyFollowing;

    if (shouldFollow && !followerIds.contains(actor.uid)) {
      followerIds.add(actor.uid);
    }
    if (!shouldFollow) {
      followerIds.removeWhere((id) => id == actor.uid);
    }

    await _firestoreClient.setDocument(
      collectionPath: vendor.collection,
      documentId: vendor.id,
      idToken: idToken,
      data: <String, dynamic>{
        ...vendor.data,
        'followerIds': followerIds,
        'updatedAt': _nowIso(),
      },
    );

    await _updateActorFollowing(
      idToken: idToken,
      actorUid: actor.uid,
      vendorId: vendor.id,
      follow: shouldFollow,
    );

    return await getVendorRelationship(
      idToken: idToken,
      vendorId: vendor.id,
      role: actor.role,
    );
  }

  Future<Map<String, dynamic>> listFollowing({
    required String idToken,
    String? role,
    int limit = 50,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final ids = _readStringList(actor.profile['followingIds']);
    final safeLimit = limit.clamp(1, 200).toInt();

    final items = <Map<String, dynamic>>[];
    for (final vendorId in ids.take(safeLimit)) {
      final vendor = await _tryGetVendor(idToken: idToken, vendorId: vendorId);
      if (vendor == null) {
        items.add(<String, dynamic>{'vendorId': vendorId});
        continue;
      }
      items.add(<String, dynamic>{
        'vendorId': vendor.id,
        'name': _optionalText(vendor.data['name']) ?? '',
        'profileImage': _optionalText(vendor.data['profileImage']) ?? '',
        'title': _optionalText(vendor.data['title']) ?? '',
        'subscriptionStatus':
            _optionalText(vendor.data['subscriptionStatus']) ?? '',
        'collection': vendor.collection,
      });
    }

    return <String, dynamic>{
      'items': items,
      'count': items.length,
      'followingIds': ids,
    };
  }

  Future<Map<String, dynamic>> listVendorFollowers({
    required String idToken,
    required String vendorId,
    int limit = 100,
  }) async {
    await _resolveUid(idToken);
    final vendor =
        await _getVendorOrThrow(idToken: idToken, vendorId: vendorId);
    final followerIds = _readStringList(vendor.data['followerIds']);
    final safeLimit = limit.clamp(1, 300).toInt();

    final items = <Map<String, dynamic>>[];
    for (final userId in followerIds.take(safeLimit)) {
      final profile = await _tryGetAnyUser(idToken: idToken, userId: userId);
      if (profile == null) {
        items.add(<String, dynamic>{'userId': userId});
        continue;
      }
      items.add(<String, dynamic>{
        'userId': userId,
        'role': profile.role,
        'name': profile.name,
        'profileImage': profile.image,
      });
    }

    return <String, dynamic>{
      'vendorId': vendor.id,
      'items': items,
      'count': items.length,
      'followerIds': followerIds,
    };
  }

  Future<Map<String, dynamic>> listFavorites({
    required String idToken,
    int limit = 50,
    String? pageToken,
  }) async {
    final uid = await _resolveUid(idToken);
    final safeLimit = limit.clamp(1, 200).toInt();
    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'users/$uid/favorites',
      idToken: idToken,
      pageSize: safeLimit,
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );

    return <String, dynamic>{
      'items': page.documents,
      'count': page.documents.length,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> getFavorite({
    required String idToken,
    required String postId,
  }) async {
    final uid = await _resolveUid(idToken);
    final favorite = await _firestoreClient.getDocument(
      collectionPath: 'users/$uid/favorites',
      documentId: postId.trim(),
      idToken: idToken,
    );
    return <String, dynamic>{
      'postId': postId.trim(),
      'isFavorite': favorite != null,
      'favorite': favorite,
    };
  }

  Future<Map<String, dynamic>> setFavorite({
    required String idToken,
    required String postId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final id = postId.trim();
    if (id.isEmpty) throw ApiException.badRequest('post_id is required.');

    final current = await _firestoreClient.getDocument(
      collectionPath: 'users/$uid/favorites',
      documentId: id,
      idToken: idToken,
    );

    final explicit = _asBool(payload['isFavorite']);
    final shouldFavorite = explicit ?? current == null;

    if (!shouldFavorite) {
      await _firestoreClient.deleteDocument(
        collectionPath: 'users/$uid/favorites',
        documentId: id,
        idToken: idToken,
      );
      return <String, dynamic>{'postId': id, 'isFavorite': false};
    }

    final now = _nowIso();
    final favorite = <String, dynamic>{
      'postId': id,
      'timestamp': now,
      'createdAt': now,
      ..._safeFavoriteExtras(payload),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'users/$uid/favorites',
      documentId: id,
      idToken: idToken,
      data: favorite,
    );
    return <String, dynamic>{
      'postId': id,
      'isFavorite': true,
      'favorite': favorite
    };
  }

  Future<Map<String, dynamic>> deleteFavorite({
    required String idToken,
    required String postId,
  }) async {
    final uid = await _resolveUid(idToken);
    await _firestoreClient.deleteDocument(
      collectionPath: 'users/$uid/favorites',
      documentId: postId.trim(),
      idToken: idToken,
    );
    return <String, dynamic>{'postId': postId.trim(), 'isFavorite': false};
  }

  Future<void> _updateActorFollowing({
    required String idToken,
    required String actorUid,
    required String vendorId,
    required bool follow,
  }) async {
    for (final collection in const <String>[
      'customers',
      'vendors',
      'artisans'
    ]) {
      final profile = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: actorUid,
        idToken: idToken,
      );
      if (profile == null) continue;
      final followingIds = _readStringList(profile['followingIds']);
      if (follow && !followingIds.contains(vendorId)) {
        followingIds.add(vendorId);
      }
      if (!follow) {
        followingIds.removeWhere((id) => id == vendorId);
      }
      await _firestoreClient.setDocument(
        collectionPath: collection,
        documentId: actorUid,
        idToken: idToken,
        data: <String, dynamic>{
          ...profile,
          'followingIds': followingIds,
          'updatedAt': _nowIso(),
        },
      );
    }
  }

  Future<_VendorDoc?> _tryGetVendor({
    required String idToken,
    required String vendorId,
  }) async {
    for (final collection in const <String>['vendors', 'artisans']) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: vendorId.trim(),
        idToken: idToken,
      );
      if (doc != null) {
        return _VendorDoc(
          id: vendorId.trim(),
          collection: collection,
          data: doc,
        );
      }
    }
    return null;
  }

  Future<_VendorDoc> _getVendorOrThrow({
    required String idToken,
    required String vendorId,
  }) async {
    final id = vendorId.trim();
    if (id.isEmpty) throw ApiException.badRequest('vendor_id is required.');
    final doc = await _tryGetVendor(idToken: idToken, vendorId: id);
    if (doc == null) throw ApiException.notFound('Vendor not found.');
    return doc;
  }

  Future<_UserProfile?> _tryGetAnyUser({
    required String idToken,
    required String userId,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) return null;

    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('customers', 'customer'),
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: id,
        idToken: idToken,
      );
      if (doc == null) continue;
      return _UserProfile(
        role: pair.value,
        name: _optionalText(doc['username']) ??
            _optionalText(doc['name']) ??
            'User',
        image: _optionalText(doc['profileImage']) ?? '',
      );
    }
    return null;
  }

  Future<_Actor> _resolveActor({
    required String idToken,
    String? roleHint,
  }) async {
    final uid = await _resolveUid(idToken);
    final hint = roleHint?.trim().toLowerCase();
    if (hint == 'customer') {
      final customer = await _firestoreClient.getDocument(
        collectionPath: 'customers',
        documentId: uid,
        idToken: idToken,
      );
      return _Actor(
        uid: uid,
        role: 'customer',
        profile: customer ?? const <String, dynamic>{},
      );
    }

    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
      MapEntry<String, String>('customers', 'customer'),
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        return _Actor(uid: uid, role: pair.value, profile: doc);
      }
    }

    return _Actor(
      uid: uid,
      role: hint == 'customer' ? 'customer' : 'vendor',
      profile: const <String, dynamic>{},
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

  Map<String, dynamic> _safeFavoriteExtras(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};
    for (final key in const <String>[
      'content',
      'imageUrl',
      'artisanId',
      'caption',
      'type',
    ]) {
      if (payload.containsKey(key)) out[key] = payload[key];
    }
    return out;
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  String _nextId({required String prefix}) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  String? _optionalText(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}

class _Actor {
  const _Actor({
    required this.uid,
    required this.role,
    required this.profile,
  });

  final String uid;
  final String role;
  final Map<String, dynamic> profile;
}

class _VendorDoc {
  const _VendorDoc({
    required this.id,
    required this.collection,
    required this.data,
  });

  final String id;
  final String collection;
  final Map<String, dynamic> data;
}

class _UserProfile {
  const _UserProfile({
    required this.role,
    required this.name,
    required this.image,
  });

  final String role;
  final String name;
  final String image;
}
