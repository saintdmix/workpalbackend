import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final profileService = ProfileService();

class ProfileService {
  ProfileService({
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

    // Also pull the consolidated user document to avoid returning an incomplete profile.
    final legacyProfile = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final merged = <String, dynamic>{
      if (legacyProfile != null) ...legacyProfile,
      if (roleProfile != null) ...roleProfile,
      'uid': uid,
      'email': email,
      'role': normalizedRole,
      'createdAt': (roleProfile ?? legacyProfile)?['createdAt'] ?? now,
      'updatedAt': now,
    };

    // Persist the merged profile so subsequent reads stay consistent.
    await _firestoreClient.setDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
      data: merged,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
      data: merged,
    );

    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: uid,
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
          'No editable profile fields were provided.');
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

  Map<String, dynamic> _sanitizeUpdates(Map<String, dynamic> updates) {
    const blocked = <String>{'uid', 'email', 'role', 'createdAt', 'updatedAt'};
    final sanitized = <String, dynamic>{};

    for (final entry in updates.entries) {
      if (blocked.contains(entry.key)) continue;
      sanitized[entry.key] = entry.value;
    }

    return sanitized;
  }
}
