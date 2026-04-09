import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/services/review_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];

    final contentType = request.headers[HttpHeaders.contentTypeHeader] ?? '';
    final Map<String, dynamic> payload;

    if (contentType.contains('multipart/form-data')) {
      late final FormData formData;
      try {
        formData = await request.formData();
      } catch (_) {
        throw ApiException.badRequest(
          'Invalid multipart/form-data. Do not set Content-Type manually; '
          'let your client include the multipart boundary.',
        );
      }

      final fields = <String, dynamic>{};
      for (final entry in formData.fields.entries) {
        fields[entry.key] = _coerceFormValue(entry.key, entry.value);
      }

      final uploadedImageUrls = <String>[];
      for (final entry in formData.files.entries) {
        final key = entry.key.trim().toLowerCase();
        final file = entry.value;

        if (key != 'image' &&
            key != 'images' &&
            key != 'photo' &&
            key != 'photos' &&
            !key.startsWith('image') &&
            !key.startsWith('photo')) {
          continue;
        }

        final bytes = await file.readAsBytes();
        final uploaded = await mediaUploadService.uploadBytesForPath(
          idToken: idToken,
          bytes: bytes,
          folder: 'review_images',
          defaultNamePrefix: 'review_image',
          fileName: file.name,
          contentType: file.contentType.mimeType,
        );

        final url = '${uploaded['downloadUrl'] ?? ''}'.trim();
        if (url.isNotEmpty) {
          uploadedImageUrls.add(url);
        }
      }

      if (uploadedImageUrls.isNotEmpty) {
        final existing = _readStringList(fields['photoUrls']);
        fields['photoUrls'] = <String>[...existing, ...uploadedImageUrls];
      }

      payload = fields;
    } else {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      payload = body;
    }

    final created = await reviewService.createReview(
      idToken: idToken,
      role: role,
      payload: payload,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}

dynamic _coerceFormValue(String key, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  if (value == 'true') return true;
  if (value == 'false') return false;

  if ((value.startsWith('{') && value.endsWith('}')) ||
      (value.startsWith('[') && value.endsWith(']'))) {
    try {
      return jsonDecode(value);
    } catch (_) {}
  }

  final asNum = num.tryParse(value);
  if (asNum != null) return asNum;

  return raw;
}

List<String> _readStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
  }
  return const <String>[];
}
