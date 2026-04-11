import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/chat_service.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String chat_room_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing chat_room_id in URL path.');
    }
    final chatRoomId = segments[segments.length - 2];

    if (request.method == HttpMethod.get) {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 50;
      final pageToken = request.uri.queryParameters['pageToken'];
      final result = await chatService.listMessages(
        idToken: idToken,
        chatRoomId: chatRoomId,
        role: role,
        limit: limit,
        pageToken: pageToken,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final contentType = request.headers[HttpHeaders.contentTypeHeader] ?? '';
    final Map<String, dynamic> body;

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
      String? uploadedAudioUrl;

      for (final entry in formData.files.entries) {
        final key = entry.key.trim();
        final normalizedKey = key.toLowerCase();
        final file = entry.value;

        if (!_isChatMediaKey(key)) continue;

        final mime = file.contentType.mimeType.toLowerCase();
        final isVideo = mime.startsWith('video/') || _isVideoKey(normalizedKey);
        final isAudio = mime.startsWith('audio/') || _isAudioKey(normalizedKey);
        final isImage = mime.startsWith('image/') || _isImageKey(normalizedKey);

        if (!isVideo && !isAudio && !isImage) {
          throw ApiException.badRequest(
            'Unsupported media type: ${file.contentType.mimeType}.',
          );
        }

        final bytes = await file.readAsBytes();
        if (isVideo && bytes.length > _maxVideoBytes) {
          throw ApiException.badRequest('Video must not exceed 20MB.');
        }

        final uploaded = await mediaUploadService.uploadBytesForPath(
          idToken: idToken,
          bytes: bytes,
          folder: isVideo
              ? 'chat_videos'
              : isAudio
              ? 'chat_audios'
              : 'chat_images',
          defaultNamePrefix: isVideo
              ? 'chat_video'
              : isAudio
              ? 'chat_audio'
              : 'chat_image',
          fileName: file.name,
          contentType: file.contentType.mimeType,
        );

        final url = '${uploaded['downloadUrl'] ?? ''}'.trim();
        if (url.isEmpty) continue;

        if (isVideo) {
          uploadedVideoUrls.add(url);
        } else if (isAudio) {
          uploadedAudioUrl = url;
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

      if ((uploadedAudioUrl ?? '').isNotEmpty) {
        fields['audioUrl'] = uploadedAudioUrl;
      }

      body = fields;
    } else {
      final decoded = await request.json();
      if (decoded is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      body = decoded;
    }

    final result = await chatService.sendMessage(
      idToken: idToken,
      chatRoomId: chatRoomId,
      payload: body,
      role: role,
    );
    return Response.json(statusCode: HttpStatus.created, body: result);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}

const _maxVideoBytes = 20 * 1024 * 1024;

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

bool _isChatMediaKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  return normalized == 'media' ||
      normalized == 'file' ||
      normalized == 'files' ||
      normalized == 'attachment' ||
      normalized == 'attachments' ||
      _isImageKey(normalized) ||
      _isVideoKey(normalized) ||
      _isAudioKey(normalized) ||
      normalized.startsWith('media') ||
      normalized.startsWith('file') ||
      normalized.startsWith('attachment') ||
      normalized.startsWith('image') ||
      normalized.startsWith('video') ||
      normalized.startsWith('audio');
}

bool _isImageKey(String normalizedKey) {
  return normalizedKey == 'image' ||
      normalizedKey == 'images' ||
      normalizedKey == 'imageurl' ||
      normalizedKey == 'imageurls' ||
      normalizedKey == 'imageurls[]' ||
      normalizedKey.startsWith('image');
}

bool _isVideoKey(String normalizedKey) {
  return normalizedKey == 'video' ||
      normalizedKey == 'videos' ||
      normalizedKey == 'videourl' ||
      normalizedKey == 'videourls' ||
      normalizedKey == 'videourls[]' ||
      normalizedKey.startsWith('video');
}

bool _isAudioKey(String normalizedKey) {
  return normalizedKey == 'audio' ||
      normalizedKey == 'audios' ||
      normalizedKey == 'audiourl' ||
      normalizedKey == 'audiourls' ||
      normalizedKey == 'audiourls[]' ||
      normalizedKey.startsWith('audio');
}
