import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/hiring_service.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];

    if (request.method == HttpMethod.get) {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 30;
      final status = request.uri.queryParameters['status'];
      final jobId = request.uri.queryParameters['jobId'];
      final chatRoomId = request.uri.queryParameters['chatRoomId'];

      final result = await hiringService.listQuotes(
        idToken: idToken,
        role: role,
        chatRoomId: chatRoomId,
        limit: limit,
        status: status,
        jobId: jobId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

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
        fields[entry.key] = _coerceFormValue(entry.value);
      }

      final uploadedImageUrls = <String>[];
      final uploadedVideoUrls = <String>[];

      for (final entry in formData.files.entries) {
        final key = entry.key.trim();
        final file = entry.value;
        if (!_isQuoteMediaKey(key)) continue;

        final bytes = await file.readAsBytes();
        final isVideo =
            _isVideoKey(key) ||
            file.contentType.mimeType.toLowerCase().startsWith('video/');

        final uploaded = await mediaUploadService.uploadBytesForPath(
          idToken: idToken,
          bytes: bytes,
          folder: isVideo ? 'quote_videos' : 'quote_images',
          defaultNamePrefix: isVideo ? 'quote_video' : 'quote_image',
          fileName: file.name,
          contentType: file.contentType.mimeType,
        );

        final url = '${uploaded['downloadUrl'] ?? ''}'.trim();
        if (url.isEmpty) continue;
        if (isVideo) {
          uploadedVideoUrls.add(url);
        } else {
          uploadedImageUrls.add(url);
        }
      }

      if (uploadedImageUrls.isNotEmpty) {
        fields['imageUrls'] = <String>[
          ..._readStringList(fields['imageUrls']),
          ...uploadedImageUrls,
        ];
      }

      if (uploadedVideoUrls.isNotEmpty) {
        fields['videoUrls'] = <String>[
          ..._readStringList(fields['videoUrls']),
          ...uploadedVideoUrls,
        ];
      }

      payload = fields;
    } else {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      payload = body;
    }

    final created = await hiringService.createQuote(
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

dynamic _coerceFormValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  if (value == 'true') return true;
  if (value == 'false') return false;

  // Support sending arrays/objects as JSON strings (ex: quoteData, imageUrls).
  if ((value.startsWith('{') && value.endsWith('}')) ||
      (value.startsWith('[') && value.endsWith(']'))) {
    try {
      return jsonDecode(value);
    } catch (_) {
      // Fall through to number/string parsing.
    }
  }

  final asNum = num.tryParse(value);
  if (asNum != null) return asNum;

  return raw;
}

bool _isQuoteMediaKey(String key) {
  final normalized = key.trim().toLowerCase();
  return _isImageKey(normalized) ||
      _isVideoKey(normalized) ||
      normalized.startsWith('image') ||
      normalized.startsWith('video');
}

bool _isImageKey(String normalizedKey) {
  return normalizedKey == 'image' ||
      normalizedKey == 'images' ||
      normalizedKey == 'imageurl' ||
      normalizedKey == 'imageurls';
}

bool _isVideoKey(String normalizedKey) {
  return normalizedKey == 'video' ||
      normalizedKey == 'videos' ||
      normalizedKey == 'videourl' ||
      normalizedKey == 'videourls';
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
      } catch (_) {
        // ignore
      }
    }
  }
  return const <String>[];
}
