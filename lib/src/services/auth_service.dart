import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final authService = AuthService();

class AuthService {
  AuthService({
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

  Future<Map<String, dynamic>> signUpCustomer(Map<String, dynamic> payload) {
    return _signUp(payload, role: 'customer', collection: 'customers');
  }

  Future<Map<String, dynamic>> signInCustomer(Map<String, dynamic> payload) {
    return _signIn(payload, role: 'customer', collection: 'customers');
  }

  Future<Map<String, dynamic>> signUpArtisan(Map<String, dynamic> payload) {
    return _signUp(payload, role: 'artisan', collection: 'artisans');
  }

  Future<Map<String, dynamic>> signInArtisan(Map<String, dynamic> payload) {
    return _signIn(payload, role: 'artisan', collection: 'artisans');
  }

  Future<Map<String, dynamic>> _signUp(
    Map<String, dynamic> payload, {
    required String role,
    required String collection,
  }) async {
    final email = _requiredString(payload, 'email');
    final password = _requiredString(payload, 'password');
    final displayName = _optionalString(payload, 'fullName');
    final now = DateTime.now().toUtc().toIso8601String();

    final authData = await _authClient.signUp(
      email: email,
      password: password,
      displayName: displayName,
    );

    final idToken = '${authData['idToken'] ?? ''}';
    final uid = '${authData['localId'] ?? ''}';
    if (idToken.isEmpty || uid.isEmpty) {
      throw ApiException.internal('Missing auth token from Firebase.');
    }

    final profile = <String, dynamic>{
      'uid': uid,
      'userId': uid,
      'users': uid,
      'email': email,
      'role': role,
      'createdAt': now,
      'updatedAt': now,
      ..._profileDataFromPayload(payload),
    };

    await _firestoreClient.setDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
      data: profile,
    );

    final referralId =
        _optionalString(payload, 'referralId') ?? _generateReferralCode();
    final legacy = <String, dynamic>{
      ...profile,
      'userId': uid,
      'users': uid,
      'username': _optionalString(payload, 'username') ??
          _optionalString(payload, 'name') ??
          _optionalString(payload, 'fullName') ??
          '',
      'name': _optionalString(payload, 'name') ??
          _optionalString(payload, 'fullName') ??
          _optionalString(payload, 'username') ??
          '',
      'referralId': referralId,
      'points': profile['points'] ?? 0,
      'phoneNumber': _optionalString(payload, 'phoneNumber') ??
          _optionalString(payload, 'phone') ??
          '',
      'imageUrl': _optionalString(payload, 'imageUrl') ??
          _optionalString(payload, 'profileImage') ??
          '',
      'profileImage': _optionalString(payload, 'profileImage') ??
          _optionalString(payload, 'imageUrl') ??
          '',
      'lastTimeOnline': now,
      'updatedAt': now,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
      data: legacy,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: uid,
      idToken: idToken,
      data: legacy,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'referralId',
      documentId: referralId,
      idToken: idToken,
      data: <String, dynamic>{
        ...legacy,
        'referralId': referralId,
      },
    );

    return <String, dynamic>{
      'message': '${_capitalize(role)} account created successfully.',
      'uid': uid,
      'email': email,
      'idToken': idToken,
      'refreshToken': authData['refreshToken'],
      'profile': profile,
    };
  }

  Future<Map<String, dynamic>> _signIn(
    Map<String, dynamic> payload, {
    required String role,
    required String collection,
  }) async {
    final email = _requiredString(payload, 'email');
    final password = _requiredString(payload, 'password');

    final authData = await _authClient.signIn(email: email, password: password);
    final idToken = '${authData['idToken'] ?? ''}';
    final uid = '${authData['localId'] ?? ''}';
    if (idToken.isEmpty || uid.isEmpty) {
      throw ApiException.internal('Missing auth token from Firebase.');
    }

    var profile = await _firestoreClient.getDocument(
      collectionPath: collection,
      documentId: uid,
      idToken: idToken,
    );

    if (profile == null) {
      final now = DateTime.now().toUtc().toIso8601String();
      profile = <String, dynamic>{
        'uid': uid,
        'userId': uid,
        'users': uid,
        'email': email,
        'role': role,
        'createdAt': now,
        'updatedAt': now,
      };
      await _firestoreClient.setDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
        data: profile,
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final referralId =
        _optionalString(profile, 'referralId') ?? _generateReferralCode();
    final legacy = <String, dynamic>{
      ...profile,
      'uid': uid,
      'userId': uid,
      'users': uid,
      'email': email,
      'role': role,
      'referralId': referralId,
      'updatedAt': now,
      if (_optionalString(profile, 'createdAt') == null) 'createdAt': now,
    };
    await _firestoreClient.setDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
      data: legacy,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'userId',
      documentId: uid,
      idToken: idToken,
      data: legacy,
    );
    await _firestoreClient.setDocument(
      collectionPath: 'referralId',
      documentId: referralId,
      idToken: idToken,
      data: <String, dynamic>{...legacy, 'referralId': referralId},
    );

    return <String, dynamic>{
      'message': '${_capitalize(role)} sign in successful.',
      'uid': uid,
      'email': email,
      'idToken': idToken,
      'refreshToken': authData['refreshToken'],
      'profile': profile,
    };
  }

  String _requiredString(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    throw ApiException.badRequest('$key is required.');
  }

  String? _optionalString(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  Map<String, dynamic> _profileDataFromPayload(Map<String, dynamic> payload) {
    final data = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      if (key == 'email' || key == 'password') continue;
      data[key] = entry.value;
    }
    return data;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _generateReferralCode({int length = 7}) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      out.write(chars[_random.nextInt(chars.length)]);
    }
    return out.toString();
  }
}
