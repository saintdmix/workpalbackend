import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/services/workfeed_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);

    if (request.method == HttpMethod.get) {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      final artisanId = request.uri.queryParameters['artisanId'];
      final filter = request.uri.queryParameters['filter'];
      final feed = request.uri.queryParameters['feed'];
      final following = _parseBool(request.uri.queryParameters['following']);
      final pageToken = request.uri.queryParameters['pageToken'];
      final latitude = _parseDoubleParam(
        request.uri.queryParameters['latitude'],
        'latitude',
      );
      final longitude = _parseDoubleParam(
        request.uri.queryParameters['longitude'],
        'longitude',
      );
      final normalizedMode = (filter ?? feed ?? '').trim().toLowerCase();
      final followingOnly =
          (following ?? false) || normalizedMode == 'following';

      if ((latitude == null) != (longitude == null)) {
        throw ApiException.badRequest(
          'latitude and longitude are required together.',
        );
      }

      final result = await workfeedService.listWorkfeeds(
        idToken: idToken,
        limit: limit,
        artisanId: artisanId,
        followingOnly: followingOnly,
        pageToken: pageToken,
        latitude: latitude,
        longitude: longitude,
      );
      return Response.json(
        body: {
          'items': result.items,
          if (result.nextPageToken != null)
            'nextPageToken': result.nextPageToken,
        },
      );
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

      final uploadedMediaUrls = <String>[];
      String? uploadedThumbnailUrl;

      for (final entry in formData.files.entries) {
        final key = entry.key.trim();
        final file = entry.value;

        final bytes = await file.readAsBytes();
        final mime = file.contentType.mimeType.toLowerCase();
        final isVideo = mime.startsWith('video/') || _isVideoKey(key);

        if (_isThumbnailKey(key)) {
          final uploaded = await mediaUploadService.uploadBytesForPath(
            idToken: idToken,
            bytes: bytes,
            folder: 'workfeed_thumbnails',
            defaultNamePrefix: 'workfeed_thumbnail',
            fileName: file.name,
            contentType: file.contentType.mimeType,
          );
          final url = '${uploaded['downloadUrl'] ?? ''}'.trim();
          if (url.isNotEmpty) uploadedThumbnailUrl = url;
          continue;
        }

        if (!_isWorkfeedMediaKey(key)) continue;

        final uploaded = await mediaUploadService.uploadBytesForPath(
          idToken: idToken,
          bytes: bytes,
          folder: isVideo ? 'workfeed_videos' : 'workfeed_images',
          defaultNamePrefix: isVideo ? 'workfeed_video' : 'workfeed_image',
          fileName: file.name,
          contentType: file.contentType.mimeType,
        );
        final url = '${uploaded['downloadUrl'] ?? ''}'.trim();
        if (url.isNotEmpty) uploadedMediaUrls.add(url);
      }

      // Merge uploaded media URLs into `imageUrl` (primary) + `mediaUrls` (alias).
      if (uploadedMediaUrls.isNotEmpty) {
        final merged = <String>[
          ..._readStringList(fields['imageUrl']),
          ..._readStringList(fields['mediaUrls']),
          ...uploadedMediaUrls,
        ];
        fields['imageUrl'] = merged;
        fields['mediaUrls'] = merged;
      }

      // Accept a `thumbnail` file upload, map it to `thumbnailUrl` for the service.
      if ((uploadedThumbnailUrl ?? '').isNotEmpty) {
        fields['thumbnailUrl'] = uploadedThumbnailUrl;
      }

      payload = fields;
    } else {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      payload = body;
    }

    final created = await workfeedService.createWorkfeed(
      idToken: idToken,
      payload: payload,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
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

dynamic _coerceFormValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  if (value == 'true') return true;
  if (value == 'false') return false;

  if ((value.startsWith('{') && value.endsWith('}')) ||
      (value.startsWith('[') && value.endsWith(']'))) {
    try {
      return jsonDecode(value);
    } catch (_) {
      // Fall through.
    }
  }

  final asNum = num.tryParse(value);
  if (asNum != null) return asNum;
  return raw;
}

List<String> _readStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().where((e) => e.trim().isNotEmpty).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .whereType<String>()
              .where((e) => e.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {
        // ignore
      }
    }
    if (trimmed.isNotEmpty) return <String>[trimmed];
  }
  return const <String>[];
}

bool _isWorkfeedMediaKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (_isThumbnailKey(normalized)) return false;

  return normalized == 'media' ||
      normalized == 'file' ||
      normalized == 'files' ||
      normalized == 'image' ||
      normalized == 'images' ||
      normalized == 'video' ||
      normalized == 'videos' ||
      normalized == 'imageurl' ||
      normalized == 'mediaurls' ||
      normalized.startsWith('media') ||
      normalized.startsWith('image') ||
      normalized.startsWith('video');
}

bool _isVideoKey(String key) {
  final normalized = key.trim().toLowerCase();
  return normalized == 'video' ||
      normalized == 'videos' ||
      normalized == 'videourl' ||
      normalized == 'videourls' ||
      normalized.startsWith('video');
}

bool _isThumbnailKey(String key) {
  final normalized = key.trim().toLowerCase();
  return normalized == 'thumbnail' ||
      normalized == 'thumb' ||
      normalized == 'thumbnailurl' ||
      normalized.startsWith('thumbnail') ||
      normalized.startsWith('thumb');
}

bool? _parseBool(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}

double? _parseDoubleParam(String? value, String name) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = double.tryParse(value.trim());
  if (parsed == null) {
    throw ApiException.badRequest('$name must be a valid number.');
  }
  return parsed;
}
