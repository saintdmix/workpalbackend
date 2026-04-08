import 'dart:convert';

import 'package:http/http.dart' as http;

import '../exceptions/api_exception.dart';

class FirebaseStorageRestClient {
  FirebaseStorageRestClient({
    required String storageBucket,
    http.Client? httpClient,
  })  : _storageBucket = storageBucket,
        _http = httpClient ?? http.Client();

  final String _storageBucket;
  final http.Client _http;

  Future<FirebaseStorageUploadResult> uploadBytes({
    required String idToken,
    required String objectPath,
    required List<int> bytes,
    required String contentType,
  }) async {
    final normalizedPath = objectPath.trim();
    if (normalizedPath.isEmpty) {
      throw ApiException.badRequest('objectPath is required.');
    }

    final uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$_storageBucket/o'
      '?name=${Uri.encodeQueryComponent(normalizedPath)}',
    );

    final response = await _http.post(
      uri,
      headers: <String, String>{
        // Firebase Storage accepts Firebase ID tokens for authenticated users.
        // The API expects the token in the Authorization header.
        'authorization': 'Bearer $idToken',
        'content-type': contentType,
      },
      body: bytes,
    );

    if (response.statusCode >= 400) {
      final detail = _readStorageError(response.body);
      throw ApiException.server(
        'Firebase Storage upload failed '
        '(HTTP ${response.statusCode}, bucket=$_storageBucket): $detail',
      );
    }

    final body = _decodeObject(response.body);
    final name = '${body['name'] ?? normalizedPath}';
    final bucket = '${body['bucket'] ?? _storageBucket}';
    final sizeBytes = int.tryParse('${body['size'] ?? bytes.length}') ?? bytes.length;
    final savedType = '${body['contentType'] ?? contentType}';
    final token = '${body['downloadTokens'] ?? ''}'.trim();

    final encodedName = Uri.encodeComponent(name);
    final downloadUrl = token.isEmpty
        ? 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedName?alt=media'
        : 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedName?alt=media&token=$token';

    return FirebaseStorageUploadResult(
      bucket: bucket,
      objectPath: name,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
      contentType: savedType,
    );
  }

  String _readStorageError(String body) {
    try {
      final decoded = _decodeObject(body);
      final error = decoded['error'];
      if (error is Map) {
        final message = '${error['message'] ?? ''}'.trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return 'Firebase Storage request failed.';
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }
}

class FirebaseStorageUploadResult {
  const FirebaseStorageUploadResult({
    required this.bucket,
    required this.objectPath,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.contentType,
  });

  final String bucket;
  final String objectPath;
  final String downloadUrl;
  final int sizeBytes;
  final String contentType;
}
