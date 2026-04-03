import 'dart:convert';
import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firebase_storage_rest_client.dart';

final mediaUploadService = MediaUploadService();

class MediaUploadService {
  MediaUploadService({
    FirebaseAuthRestClient? authClient,
    FirebaseStorageRestClient? storageClient,
  }) : _authClient =
           authClient ??
           FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
       _storageClient =
           storageClient ??
           FirebaseStorageRestClient(
             storageBucket: AppEnv.firebaseStorageBucket,
           );

  final FirebaseAuthRestClient _authClient;
  final FirebaseStorageRestClient _storageClient;
  final Random _random = Random();

  Future<Map<String, dynamic>> upload({
    required String idToken,
    required Map<String, dynamic> payload,
  }) async {
    final uid = await _resolveUid(idToken);
    final mediaBase64 = _requiredString(
      payload,
      'mediaBase64',
      aliases: const <String>['base64', 'data'],
    );
    final contentType =
        _optionalString(payload, 'contentType') ??
        _guessContentType(mediaBase64) ??
        'application/octet-stream';
    final folder = _optionalString(payload, 'folder') ?? 'uploads';
    final providedFileName = _optionalString(payload, 'fileName');
    final preserveExt = _extensionFor(contentType);
    final fileName = providedFileName?.trim().isNotEmpty == true
        ? providedFileName!.trim()
        : _nextName(uid: uid, extension: preserveExt);
    final objectPath = _buildObjectPath(folder: folder, fileName: fileName);

    final bytes = _decodeMediaBytes(mediaBase64);
    final upload = await _storageClient.uploadBytes(
      idToken: idToken,
      objectPath: objectPath,
      bytes: bytes,
      contentType: contentType,
    );

    return <String, dynamic>{
      'uploadedBy': uid,
      'objectPath': objectPath,
      'downloadUrl': upload.downloadUrl,
      'bucket': upload.bucket,
      'sizeBytes': upload.sizeBytes,
      'contentType': upload.contentType,
      'fileName': fileName,
    };
  }

  Future<Map<String, dynamic>> uploadForPath({
    required String idToken,
    required String mediaBase64,
    required String folder,
    required String defaultNamePrefix,
    String? fileName,
    String? contentType,
  }) async {
    final uid = await _resolveUid(idToken);
    final resolvedType =
        contentType ??
        _guessContentType(mediaBase64) ??
        'application/octet-stream';
    final bytes = _decodeMediaBytes(mediaBase64);
    final ext = _extensionFor(resolvedType);
    final resolvedName = (fileName ?? '').trim().isNotEmpty
        ? fileName!.trim()
        : '${defaultNamePrefix}_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999999).toString().padLeft(6, '0')}$ext';
    final objectPath = _buildObjectPath(folder: folder, fileName: resolvedName);

    final upload = await _storageClient.uploadBytes(
      idToken: idToken,
      objectPath: objectPath,
      bytes: bytes,
      contentType: resolvedType,
    );
    return <String, dynamic>{
      'uploadedBy': uid,
      'objectPath': objectPath,
      'downloadUrl': upload.downloadUrl,
      'bucket': upload.bucket,
      'sizeBytes': upload.sizeBytes,
      'contentType': upload.contentType,
      'fileName': resolvedName,
    };
  }

  Future<Map<String, dynamic>> uploadBytesForPath({
    required String idToken,
    required List<int> bytes,
    required String folder,
    required String defaultNamePrefix,
    String? fileName,
    String? contentType,
  }) async {
    final uid = await _resolveUid(idToken);
    final resolvedType =
        (contentType ?? 'application/octet-stream').trim().isEmpty
        ? 'application/octet-stream'
        : (contentType ?? 'application/octet-stream').trim();
    final ext = _extensionFor(resolvedType);
    final resolvedName = (fileName ?? '').trim().isNotEmpty
        ? fileName!.trim()
        : _nextName(
            uid: uid,
            extension: ext.isNotEmpty ? ext : '',
          );
    final objectPath = _buildObjectPath(
      folder: folder,
      fileName: resolvedName,
    );

    final upload = await _storageClient.uploadBytes(
      idToken: idToken,
      objectPath: objectPath,
      bytes: bytes,
      contentType: resolvedType,
    );

    return <String, dynamic>{
      'uploadedBy': uid,
      'objectPath': objectPath,
      'downloadUrl': upload.downloadUrl,
      'bucket': upload.bucket,
      'sizeBytes': upload.sizeBytes,
      'contentType': upload.contentType,
      'fileName': resolvedName,
    };
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  List<int> _decodeMediaBytes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ApiException.badRequest('mediaBase64 is required.');
    }

    final commaIndex = trimmed.indexOf(',');
    final encoded = trimmed.startsWith('data:')
        ? (commaIndex >= 0 ? trimmed.substring(commaIndex + 1) : '')
        : trimmed;
    if (encoded.isEmpty) {
      throw ApiException.badRequest('Invalid mediaBase64 payload.');
    }

    try {
      return base64Decode(encoded);
    } catch (_) {
      throw ApiException.badRequest('mediaBase64 is not valid base64 data.');
    }
  }

  String _buildObjectPath({
    required String folder,
    required String fileName,
  }) {
    final cleanFolder = folder
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .join('/');
    final cleanName = fileName.trim();
    if (cleanName.isEmpty) {
      throw ApiException.badRequest('fileName is required.');
    }
    if (cleanFolder.isEmpty) return cleanName;
    return '$cleanFolder/$cleanName';
  }

  String _nextName({
    required String uid,
    required String extension,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${uid}_${now}_$suffix$extension';
  }

  String? _guessContentType(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('data:')) return null;
    final semicolon = trimmed.indexOf(';');
    if (semicolon < 5) return null;
    return trimmed.substring(5, semicolon).trim();
  }

  String _extensionFor(String contentType) {
    final t = contentType.trim().toLowerCase();
    if (t == 'image/jpeg' || t == 'image/jpg') return '.jpg';
    if (t == 'image/png') return '.png';
    if (t == 'image/webp') return '.webp';
    if (t == 'video/mp4') return '.mp4';
    if (t == 'audio/aac') return '.aac';
    if (t == 'audio/mpeg') return '.mp3';
    if (t == 'audio/ogg') return '.ogg';
    if (t == 'application/pdf') return '.pdf';
    return '';
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
}
