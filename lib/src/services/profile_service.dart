import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final profileService = ProfileService();

class ProfileService {
  ProfileService({
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

  Future<Map<String, dynamic>> getProfile({
    required String role,
    required String idToken,
  }) async {
    final normalizedRole = _normalizeRole(role);
    final collection = _collectionForRole(normalizedRole);
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}';
    final email = '${user['email'] ?? ''}';

    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }

    final roleProfile = await _firestoreClient.getDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
    );

    // For artisans, also check vendors collection as profiles may live there.
    Map<String, dynamic>? vendorProfile;
    if (normalizedRole == 'artisan') {
      vendorProfile = await _firestoreClient.getDocument(
        collectionPath: 'vendors',
        documentId: uid,
        idToken: idToken,
      );
    }

    // Presence can be written to different collections depending on the client
    // role passed to /chats/presence. Pull from all known profiles and prefer
    // the one with the newest lastSeen.
    final customerPresence = normalizedRole == 'customer'
        ? roleProfile
        : await _firestoreClient.getDocument(
            collectionPath: 'customers',
            documentId: uid,
            idToken: idToken,
          );
    final vendorPresence =
        vendorProfile ??
        await _firestoreClient.getDocument(
          collectionPath: 'vendors',
          documentId: uid,
          idToken: idToken,
        );
    final artisanPresence = normalizedRole == 'artisan'
        ? roleProfile
        : await _firestoreClient.getDocument(
            collectionPath: 'artisans',
            documentId: uid,
            idToken: idToken,
          );

    // Also pull the consolidated user document to avoid returning an incomplete profile.
    final legacyProfile = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
    );

    // App token is also stored in a dedicated collection. This avoids cases
    // where the profile doc didn't exist when /profile/app_token was called.
    final appTokenDoc = await _firestoreClient.getDocument(
      collectionPath: 'app_tokens',
      documentId: uid,
      idToken: idToken,
    );
    final appToken = _optionalStringFromAny(appTokenDoc, 'appToken');

    final now = DateTime.now().toUtc().toIso8601String();
    final merged = <String, dynamic>{
      if (legacyProfile != null) ...legacyProfile,
      if (roleProfile != null) ...roleProfile,
      if (vendorProfile != null) ...vendorProfile,
      'uid': uid,
      'email': email,
      'role': normalizedRole,
      'createdAt':
          (vendorProfile ?? roleProfile ?? legacyProfile)?['createdAt'] ?? now,
      'updatedAt': now,
      'rating':
          _asDouble(
            (vendorProfile ?? roleProfile ?? legacyProfile)?['rating'],
          ) ??
          0.0,
      'ratingQuality':
          _asDouble(
            (vendorProfile ?? roleProfile ?? legacyProfile)?['ratingQuality'],
          ) ??
          0.0,
      'ratingComm':
          _asDouble(
            (vendorProfile ?? roleProfile ?? legacyProfile)?['ratingComm'],
          ) ??
          0.0,
      'ratingTimeliness':
          _asDouble(
            (vendorProfile ??
                roleProfile ??
                legacyProfile)?['ratingTimeliness'],
          ) ??
          0.0,
      'ratingValue':
          _asDouble(
            (vendorProfile ?? roleProfile ?? legacyProfile)?['ratingValue'],
          ) ??
          0.0,
      'reviewCount':
          _asInt(
            (vendorProfile ?? roleProfile ?? legacyProfile)?['reviewCount'],
          ) ??
          0,
    };

    final presenceSource = _pickLatestPresence(<Map<String, dynamic>?>[
      // Prefer role profile first when timestamps tie.
      roleProfile,
      vendorProfile,
      customerPresence,
      vendorPresence,
      artisanPresence,
      legacyProfile,
    ]);
    if (presenceSource != null) {
      merged['isOnline'] = presenceSource['isOnline'] == true;
      final lastSeen = _optionalStringFromAny(presenceSource, 'lastSeen');
      if (lastSeen != null && lastSeen.isNotEmpty)
        merged['lastSeen'] = lastSeen;
    }

    if (appToken != null && appToken.isNotEmpty) {
      merged['appToken'] = appToken;
    }

    // Persist the merged profile so subsequent reads stay consistent.
    final persistable = <String, dynamic>{...merged}..remove('appToken');

    await _firestoreClient.setDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
      data: persistable,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
      data: persistable,
    );

    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: uid,
      idToken: idToken,
      data: persistable,
    );

    final referralId = merged['referralId']?.toString();
    if (referralId != null && referralId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'referralId',
        documentId: referralId,
        idToken: idToken,
        data: <String, dynamic>{...persistable, 'referralId': referralId},
      );
    }

    return merged;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String role,
    required String idToken,
    required Map<String, dynamic> updates,
  }) async {
    final normalizedRole = _normalizeRole(role);
    final current = await getProfile(role: normalizedRole, idToken: idToken);
    final sanitizedUpdates = _sanitizeUpdates(updates);

    if (sanitizedUpdates.isEmpty) {
      throw ApiException.badRequest(
        'No editable profile fields were provided.',
      );
    }

    final merged = <String, dynamic>{
      ...current,
      ...sanitizedUpdates,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _firestoreClient.setDocument(
      collectionPath: _collectionForRole(normalizedRole),
      documentId: '${current['uid']}',
      idToken: idToken,
      data: merged,
    );

    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: '${current['uid']}',
      idToken: idToken,
      data: merged,
    );

    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: '${current['uid']}',
      idToken: idToken,
      data: merged,
    );

    final referralId = merged['referralId']?.toString();
    if (referralId != null && referralId.isNotEmpty) {
      await _firestoreClient.setDocument(
        collectionPath: 'referralId',
        documentId: referralId,
        idToken: idToken,
        data: <String, dynamic>{...merged, 'referralId': referralId},
      );
    }

    return merged;
  }

  String _normalizeRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized != 'customer' && normalized != 'artisan') {
      throw ApiException.badRequest('role must be either customer or artisan.');
    }
    return normalized;
  }

  String _collectionForRole(String role) {
    return role == 'artisan' ? 'artisans' : 'customers';
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic> _sanitizeUpdates(Map<String, dynamic> updates) {
    const blocked = <String>{'uid', 'email', 'role', 'createdAt', 'updatedAt'};
    final sanitized = <String, dynamic>{};

    for (final entry in updates.entries) {
      if (blocked.contains(entry.key)) continue;
      sanitized[entry.key] = entry.value;
    }

    return sanitized;
  }

  Map<String, dynamic>? _pickLatestPresence(List<Map<String, dynamic>?> docs) {
    Map<String, dynamic>? best;
    var bestMs = -1;

    for (final doc in docs) {
      if (doc == null) continue;
      final lastSeen = _optionalStringFromAny(doc, 'lastSeen') ?? '';
      final ms = _toEpochMs(lastSeen);
      if (ms > bestMs) {
        best = doc;
        bestMs = ms;
      }
    }

    return best;
  }

  int _toEpochMs(String iso) {
    final raw = iso.trim();
    if (raw.isEmpty) return -1;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return -1;
    return parsed.toUtc().millisecondsSinceEpoch;
  }

  String? _optionalStringFromAny(Map<String, dynamic>? payload, String key) {
    if (payload == null) return null;
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
