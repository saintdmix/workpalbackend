// Place in: lib/src/firebase/firebase_auth_rest_client.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions/api_exception.dart';

class FirebaseAuthRestClient {
  FirebaseAuthRestClient({
    required String webApiKey,
    http.Client? httpClient,
  })  : _webApiKey = webApiKey,
        _http = httpClient ?? http.Client();

  final String _webApiKey;
  final http.Client _http;

  Future<FirebaseAuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final response = await _http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_webApiKey',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    return _parseAuthSessionResponse(response);
  }

  Future<FirebaseAuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final response = await _http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_webApiKey',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    return _parseAuthSessionResponse(response);
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final session = await signUpWithEmailPassword(
      email: email,
      password: password,
    );
    return <String, dynamic>{
      'localId': session.localId,
      'idToken': session.idToken,
      'refreshToken': session.refreshToken,
      'expiresIn': session.expiresIn.toString(),
      'email': session.email,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
    };
  }

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final session = await signInWithEmailPassword(
      email: email,
      password: password,
    );
    return <String, dynamic>{
      'localId': session.localId,
      'idToken': session.idToken,
      'refreshToken': session.refreshToken,
      'expiresIn': session.expiresIn.toString(),
      'email': session.email,
    };
  }

  Future<Map<String, dynamic>> lookup({
    required String idToken,
  }) async {
    final response = await _http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$_webApiKey',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    final decoded = _decodeObject(response.body);

    if (response.statusCode >= 400) {
      final firebaseMessage =
          (decoded['error'] as Map<String, dynamic>?)?['message']?.toString() ??
              'Auth request failed';
      throw ApiException.unauthorized(
        _friendlyFirebaseAuthError(firebaseMessage),
      );
    }

    final users = decoded['users'];
    if (users is! List || users.isEmpty || users.first is! Map) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }

    return Map<String, dynamic>.from(users.first as Map);
  }

  FirebaseAuthSession _parseAuthSessionResponse(http.Response response) {
    final decoded = _decodeObject(response.body);

    if (response.statusCode >= 400) {
      final firebaseMessage =
          (decoded['error'] as Map<String, dynamic>?)?['message']?.toString() ??
              'Auth request failed';
      throw ApiException.badRequest(_friendlyFirebaseAuthError(firebaseMessage));
    }

    final localId = decoded['localId']?.toString();
    final idToken = decoded['idToken']?.toString();
    final refreshToken = decoded['refreshToken']?.toString();
    final expiresIn = decoded['expiresIn']?.toString();
    final email = decoded['email']?.toString() ?? '';

    if (localId == null ||
        idToken == null ||
        refreshToken == null ||
        expiresIn == null) {
      throw ApiException.server('Firebase Auth response is missing required fields.');
    }

    return FirebaseAuthSession(
      localId: localId,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresIn: int.tryParse(expiresIn) ?? 0,
      email: email,
    );
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.server('Unexpected response from Firebase.');
    }
    return decoded;
  }

  String _friendlyFirebaseAuthError(String firebaseMessage) {
    switch (firebaseMessage) {
      case 'EMAIL_EXISTS':
        return 'This email is already registered.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/password auth is not enabled in Firebase.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Try again later.';
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'WEAK_PASSWORD : Password should be at least 6 characters':
      case 'WEAK_PASSWORD':
        return 'Password is too weak. Use at least 6 characters.';
      case 'INVALID_ID_TOKEN':
      case 'TOKEN_EXPIRED':
        return 'Invalid or expired user token.';
      default:
        return firebaseMessage;
    }
  }
}

class FirebaseAuthSession {
  FirebaseAuthSession({
    required this.localId,
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.email,
  });

  final String localId;
  final String idToken;
  final String refreshToken;
  final int expiresIn;
  final String email;

  Map<String, dynamic> toJson() {
    return {
      'uid': localId,
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresIn': expiresIn,
      'email': email,
    };
  }
}
