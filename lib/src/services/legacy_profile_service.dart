import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';

final legacyProfileService = LegacyProfileService();

class LegacyProfileService {
  LegacyProfileService({
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

  Future<Map<String, dynamic>> getLegacyProfile({
    required String idToken,
    String? userId,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = (userId ?? actorUid).trim();
    if (targetUid.isEmpty) throw ApiException.badRequest('userId is required.');

    final usersDoc = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: targetUid,
      idToken: idToken,
    );
    final userIdDoc = await _firestoreClient.getDocument(
      collectionPath: 'userId',
      documentId: targetUid,
      idToken: idToken,
    );
    final customerDoc = await _firestoreClient.getDocument(
      collectionPath: 'customers',
      documentId: targetUid,
      idToken: idToken,
    );
    final vendorDoc = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: targetUid,
      idToken: idToken,
    );
    final artisanDoc = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: targetUid,
      idToken: idToken,
    );

    final merged = <String, dynamic>{
      ...?userIdDoc,
      ...?usersDoc,
      ...?customerDoc,
      ...?vendorDoc,
      ...?artisanDoc,
      'userId': targetUid,
      'users': targetUid,
    };

    return <String, dynamic>{
      'userId': targetUid,
      'profile': merged,
      'sources': <String, bool>{
        'users': usersDoc != null,
        'userId': userIdDoc != null,
        'customers': customerDoc != null,
        'vendors': vendorDoc != null,
        'artisans': artisanDoc != null,
      },
    };
  }

  Future<Map<String, dynamic>> upsertLegacyProfile({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final actorUid = await _resolveUid(idToken);
    final targetUid = _optionalString(payload, 'userId') ??
        _optionalString(payload, 'uid') ??
        actorUid;
    final role = _optionalString(payload, 'role')?.toLowerCase();
    final syncRoleCollection = payload['syncRoleCollection'] != false;
    final now = _nowIso();

    final mediaBase64 = _optionalString(payload, 'mediaBase64');
    var profileImage = _optionalString(payload, 'profileImage') ??
        _optionalString(payload, 'imageUrl') ??
        '';
    if (mediaBase64 != null && mediaBase64.isNotEmpty) {
      final uploaded = await _mediaService.uploadForPath(
        idToken: idToken,
        mediaBase64: mediaBase64,
        folder: 'profiles/$targetUid',
        defaultNamePrefix: 'profile',
        fileName: _optionalString(payload, 'fileName'),
        contentType: _optionalString(payload, 'contentType'),
      );
      profileImage = '${uploaded['downloadUrl'] ?? ''}';
    }

    final update = <String, dynamic>{
      ..._safeProfilePayload(payload),
      'userId': targetUid,
      'users': targetUid,
      if (profileImage.isNotEmpty) 'profileImage': profileImage,
      if (profileImage.isNotEmpty) 'imageUrl': profileImage,
      'updatedAt': now,
      if (_optionalString(payload, 'createdAt') == null) 'createdAt': now,
    };

    final usersDoc = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: targetUid,
      idToken: idToken,
    );
    final userIdDoc = await _firestoreClient.getDocument(
      collectionPath: 'userId',
      documentId: targetUid,
      idToken: idToken,
    );

    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: targetUid,
      idToken: idToken,
      data: <String, dynamic>{
        ...?usersDoc,
        ...update,
        'name': update['name'] ?? update['username'] ?? usersDoc?['name'] ?? '',
      },
    );
    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: targetUid,
      idToken: idToken,
      data: <String, dynamic>{
        ...?userIdDoc,
        ...update,
        'username': update['username'] ??
            update['name'] ??
            userIdDoc?['username'] ??
            '',
      },
    );

    if (syncRoleCollection && role != null && role.isNotEmpty) {
      final collection = _roleCollection(role);
      if (collection != null) {
        final current = await _firestoreClient.getDocument(
          collectionPath: collection,
          documentId: targetUid,
          idToken: idToken,
        );
        await _firestoreClient.setDocument(
          collectionPath: collection,
          documentId: targetUid,
          idToken: idToken,
          data: <String, dynamic>{...?current, ...update, 'role': role},
        );
      }
    }

    final referralId = _optionalString(payload, 'referralId');
    if (referralId != null && referralId.isNotEmpty) {
      await _upsertReferralCodeDocument(
        idToken: idToken,
        code: referralId,
        userId: targetUid,
        profileUpdate: update,
      );
    }

    return await getLegacyProfile(idToken: idToken, userId: targetUid);
  }

  Future<Map<String, dynamic>> ensureReferralId({
    required String idToken,
    bool regenerate = false,
  }) async {
    final uid = await _resolveUid(idToken);
    final profile = await getLegacyProfile(idToken: idToken, userId: uid);
    final data = profile['profile'] is Map<String, dynamic>
        ? profile['profile'] as Map<String, dynamic>
        : <String, dynamic>{};
    var code = '${data['referralId'] ?? ''}'.trim();
    if (regenerate || code.isEmpty) {
      code = await _createUniqueReferralCode(idToken);
    }

    await upsertLegacyProfile(
      idToken: idToken,
      payload: <String, dynamic>{
        'userId': uid,
        ...data,
        'referralId': code,
      },
    );

    return <String, dynamic>{'userId': uid, 'referralId': code};
  }

  Future<Map<String, dynamic>> applyReferralCode({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final code = _requiredString(payload, 'referralId',
        aliases: const <String>['referralCode', 'code']);
    final reward = _asInt(payload['rewardPoints']) ?? 500;
    final now = _nowIso();

    final referrer = await _findReferrerByCode(
      idToken: idToken,
      code: code,
    );
    if (referrer == null) {
      throw ApiException.notFound('Referral code not found.');
    }
    if (referrer.userId == uid) {
      throw ApiException.badRequest('You cannot use your own referral code.');
    }

    final me = await getLegacyProfile(idToken: idToken, userId: uid);
    final myProfile = me['profile'] is Map<String, dynamic>
        ? me['profile'] as Map<String, dynamic>
        : <String, dynamic>{};
    final referredUser = <String, dynamic>{
      'userId': uid,
      'name': _optionalText(myProfile['name']) ??
          _optionalText(myProfile['username']) ??
          'User',
      'email': _optionalText(myProfile['email']) ?? '',
      'signupDate': now,
    };

    for (final collection in const <String>[
      'vendors',
      'customers',
      'users',
      'userId',
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: referrer.userId,
        idToken: idToken,
      );
      if (doc == null) continue;
      final points = _asInt(doc['points']) ?? 0;
      final referredUsers = _readListOfMap(doc['referredUsers']);
      final exists =
          referredUsers.any((entry) => '${entry['userId'] ?? ''}' == uid);
      if (!exists) {
        referredUsers.add(referredUser);
      }
      await _firestoreClient.setDocument(
        collectionPath: collection,
        documentId: referrer.userId,
        idToken: idToken,
        data: <String, dynamic>{
          ...doc,
          'points': points + reward,
          'referredUsers': referredUsers,
          'updatedAt': now,
        },
      );
    }

    final referralDoc = await _firestoreClient.getDocument(
      collectionPath: 'referralId',
      documentId: code,
      idToken: idToken,
    );
    if (referralDoc != null) {
      final referralPoints = _asInt(referralDoc['points']) ?? 0;
      final referralUsers = _readListOfMap(referralDoc['referredUsers']);
      final alreadyListed =
          referralUsers.any((entry) => '${entry['userId'] ?? ''}' == uid);
      if (!alreadyListed) {
        referralUsers.add(referredUser);
      }
      await _firestoreClient.setDocument(
        collectionPath: 'referralId',
        documentId: code,
        idToken: idToken,
        data: <String, dynamic>{
          ...referralDoc,
          'points': referralPoints + reward,
          'referredUsers': referralUsers,
          'updatedAt': now,
        },
      );
    }

    await _firestoreClient.createDocument(
      collectionPath: 'referral_claims',
      idToken: idToken,
      data: <String, dynamic>{
        'referralId': code,
        'referrerId': referrer.userId,
        'claimedBy': uid,
        'rewardPoints': reward,
        'timestamp': now,
      },
    );

    return <String, dynamic>{
      'referralId': code,
      'referrerId': referrer.userId,
      'claimedBy': uid,
      'rewardPoints': reward,
      'appliedAt': now,
    };
  }

  Future<void> _upsertReferralCodeDocument({
    required String idToken,
    required String code,
    required String userId,
    required Map<String, dynamic> profileUpdate,
  }) async {
    final current = await _firestoreClient.getDocument(
      collectionPath: 'referralId',
      documentId: code,
      idToken: idToken,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'referralId',
      documentId: code,
      idToken: idToken,
      data: <String, dynamic>{
        ...?current,
        'referralId': code,
        'userId': userId,
        'users': userId,
        'username': profileUpdate['username'] ?? profileUpdate['name'] ?? '',
        'name': profileUpdate['name'] ?? profileUpdate['username'] ?? '',
        'email': profileUpdate['email'] ?? '',
        'phoneNumber':
            profileUpdate['phoneNumber'] ?? profileUpdate['phone'] ?? '',
        'address':
            profileUpdate['address'] ?? profileUpdate['locationAddress'] ?? '',
        'lat': profileUpdate['lat'] ?? 0.0,
        'lng': profileUpdate['lng'] ?? 0.0,
        'imageUrl':
            profileUpdate['imageUrl'] ?? profileUpdate['profileImage'] ?? '',
        'points': current?['points'] ?? 0,
        'updatedAt': _nowIso(),
        if (current == null) 'createdAt': _nowIso(),
      },
    );
  }

  Future<_Referrer?> _findReferrerByCode({
    required String idToken,
    required String code,
  }) async {
    for (final collection in const <String>[
      'vendors',
      'customers',
      'users',
      'userId',
    ]) {
      final id = await _firestoreClient.findDocumentIdByField(
        collection: collection,
        field: 'referralId',
        value: code,
        idToken: idToken,
      );
      if (id != null && id.trim().isNotEmpty) {
        return _Referrer(userId: id.trim(), collection: collection);
      }
    }

    final legacy = await _firestoreClient.getDocument(
      collectionPath: 'referralId',
      documentId: code,
      idToken: idToken,
    );
    if (legacy != null) {
      final uid = '${legacy['userId'] ?? legacy['users'] ?? ''}'.trim();
      if (uid.isNotEmpty) {
        return _Referrer(userId: uid, collection: 'referralId');
      }
    }
    return null;
  }

  Future<String> _createUniqueReferralCode(String idToken) async {
    var attempts = 0;
    while (attempts < 12) {
      final candidate = _nextReferral();
      final exists = await _firestoreClient.getDocument(
        collectionPath: 'referralId',
        documentId: candidate,
        idToken: idToken,
      );
      if (exists == null) return candidate;
      attempts++;
    }
    throw ApiException.server('Unable to generate referral code. Try again.');
  }

  String _nextReferral() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final out = StringBuffer();
    for (var i = 0; i < 7; i++) {
      out.write(chars[_random.nextInt(chars.length)]);
    }
    return out.toString();
  }

  Map<String, dynamic> _safeProfilePayload(Map<String, dynamic> payload) {
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      final k = entry.key;
      if (k == 'mediaBase64' ||
          k == 'contentType' ||
          k == 'fileName' ||
          k == 'folder' ||
          k == 'syncRoleCollection' ||
          k == 'rewardPoints' ||
          k == 'referralCode' ||
          k == 'code') {
        continue;
      }
      out[k] = entry.value;
    }
    return out;
  }

  String? _roleCollection(String role) {
    switch (role.trim().toLowerCase()) {
      case 'customer':
        return 'customers';
      case 'vendor':
        return 'vendors';
      case 'artisan':
        return 'artisans';
      default:
        return null;
    }
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  List<Map<String, dynamic>> _readListOfMap(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>)
        out.add(Map<String, dynamic>.from(item));
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty)
      return int.tryParse(value.trim());
    return null;
  }

  String _requiredString(
    Map<String, dynamic> payload,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    for (final candidate in <String>[key, ...aliases]) {
      final value = payload[candidate];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
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

  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}

class _Referrer {
  const _Referrer({
    required this.userId,
    required this.collection,
  });

  final String userId;
  final String collection;
}
