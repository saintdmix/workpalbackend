import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mime/mime.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/services/profile_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final role = request.uri.queryParameters['role'];
    if (role == null || role.trim().isEmpty) {
      throw ApiException.badRequest(
        'Query parameter role is required (customer|artisan).',
      );
    }

    final idToken = requireBearerToken(request);

    if (request.method == HttpMethod.get) {
      final profile = await profileService.getProfile(
        role: role,
        idToken: idToken,
      );
      return Response.json(statusCode: HttpStatus.ok, body: profile);
    }

    final isMultipart = (request.headers['content-type'] ?? '')
        .toLowerCase()
        .contains('multipart/form-data');
    final body = isMultipart
        ? await _parseMultipartAndMaybeUpload(
            request: request,
            idToken: idToken,
          )
        : await _readJsonBody(request);

    final updated = await profileService.updateProfile(
      role: role,
      idToken: idToken,
      updates: body,
    );
    return Response.json(statusCode: HttpStatus.ok, body: updated);
  } on ApiException catch (e) {
    return Response.json(
      statusCode: e.statusCode,
      body: {'error': e.message},
    );
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}

Future<Map<String, dynamic>> _readJsonBody(Request request) async {
  final body = await request.json();
  if (body is! Map<String, dynamic>) {
    throw ApiException.badRequest('Request body must be a JSON object.');
  }
  return body;
}

Future<Map<String, dynamic>> _parseMultipartAndMaybeUpload({
  required Request request,
  required String idToken,
}) async {
  final contentType = request.headers['content-type'] ?? '';
  final boundary = _boundaryFromContentType(contentType);
  if (boundary == null || boundary.isEmpty) {
    throw ApiException.badRequest('Missing multipart boundary.');
  }

  final transformer = MimeMultipartTransformer(boundary);
  final parts = await transformer.bind(request.bytes()).toList();

  final fields = <String, dynamic>{};
  final files = <String, _FormFile>{};

  for (final part in parts) {
    final disposition = part.headers['content-disposition'] ?? '';
    final name = _headerValue(disposition, 'name');
    if (name == null || name.isEmpty) continue;

    final filename = _headerValue(disposition, 'filename');
    final data = await part.fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );

    if (filename != null && filename.isNotEmpty) {
      files[name] = _FormFile(
        filename: filename,
        contentType: part.headers['content-type'] ?? 'application/octet-stream',
        bytes: data,
      );
    } else {
      fields[name] = utf8.decode(data);
    }
  }

  final updates = Map<String, dynamic>.from(fields);

  // Upload supported file parts and inject resulting URLs into updates.
  final profileImageFile = _firstFile(files, const <String>[
    'profileImage',
    'profile_image',
    'avatar',
  ]);
  if (profileImageFile != null) {
    final uploaded = await mediaUploadService.uploadBytesForPath(
      idToken: idToken,
      bytes: profileImageFile.bytes,
      folder: 'profiles',
      defaultNamePrefix: 'profile',
      fileName: profileImageFile.filename,
      contentType: profileImageFile.contentType,
    );
    final url = '${uploaded['downloadUrl'] ?? ''}';
    if (url.isNotEmpty) {
      updates['profileImage'] = url;
      updates['imageUrl'] = url;
    }
  }

  final coverImageFile = _firstFile(files, const <String>[
    'coverImage',
    'cover_image',
    'cover',
  ]);
  if (coverImageFile != null) {
    final uploaded = await mediaUploadService.uploadBytesForPath(
      idToken: idToken,
      bytes: coverImageFile.bytes,
      folder: 'profiles',
      defaultNamePrefix: 'cover',
      fileName: coverImageFile.filename,
      contentType: coverImageFile.contentType,
    );
    final url = '${uploaded['downloadUrl'] ?? ''}';
    if (url.isNotEmpty) updates['coverImage'] = url;
  }

  // Try to coerce lat/lng into numbers when provided as strings.
  for (final key in <String>['lat', 'lng']) {
    if (updates[key] is String) {
      final parsed = double.tryParse(updates[key].toString());
      if (parsed != null) updates[key] = parsed;
    }
  }

  return updates;
}

String? _boundaryFromContentType(String contentType) {
  final match = RegExp(
    r'boundary=([^;]+)',
    caseSensitive: false,
  ).firstMatch(contentType);
  final raw = match?.group(1)?.trim();
  if (raw == null) return null;
  if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
    return raw.substring(1, raw.length - 1);
  }
  return raw;
}

String? _headerValue(String header, String key) {
  final match = RegExp(
    '$key="([^"]*)"',
    caseSensitive: false,
  ).firstMatch(header);
  return match?.group(1);
}

_FormFile? _firstFile(Map<String, _FormFile> files, List<String> keys) {
  for (final key in keys) {
    final file = files[key];
    if (file != null) return file;
  }
  return null;
}

class _FormFile {
  _FormFile({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;
  final String contentType;
  final List<int> bytes;
}
