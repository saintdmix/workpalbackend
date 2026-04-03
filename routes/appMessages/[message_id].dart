import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mime/mime.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/media_upload_service.dart';
import 'package:workpalbackend/src/services/nri_legacy_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String messageId) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.patch &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    if (request.method == HttpMethod.get) {
      final result = await nriLegacyService.getAppMessage(
        idToken: idToken,
        messageId: messageId,
      );
      if (result == null) {
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'App message not found.'},
        );
      }
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    if (request.method == HttpMethod.delete) {
      await nriLegacyService.deleteAppMessage(
        idToken: idToken,
        messageId: messageId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: {'deleted': true});
    }

    final isMultipart = (request.headers['content-type'] ?? '')
        .toLowerCase()
        .contains('multipart/form-data');
    final payload = isMultipart
        ? await _parseMultipartAppMessage(request: request, idToken: idToken)
        : await _readJsonBody(request);
    final result = await nriLegacyService.updateAppMessage(
      idToken: idToken,
      messageId: messageId,
      payload: payload,
    );
    return Response.json(statusCode: HttpStatus.ok, body: result);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
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

Future<Map<String, dynamic>> _parseMultipartAppMessage({
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
  _FormFile? imageFile;

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
      imageFile ??= _FormFile(
        filename: filename,
        contentType: part.headers['content-type'] ?? 'application/octet-stream',
        bytes: data,
      );
    } else {
      fields[name] = utf8.decode(data);
    }
  }

  final payload = Map<String, dynamic>.from(fields);

  if (imageFile != null) {
    final uploaded = await mediaUploadService.uploadBytesForPath(
      idToken: idToken,
      bytes: imageFile.bytes,
      folder: 'app_messages',
      defaultNamePrefix: 'app_message',
      fileName: imageFile.filename,
      contentType: imageFile.contentType,
    );
    final url = '${uploaded['downloadUrl'] ?? ''}';
    if (url.isNotEmpty) payload['imageUrl'] = url;
  }

  return payload;
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
    '$key=\"([^\"]*)\"',
    caseSensitive: false,
  ).firstMatch(header);
  return match?.group(1);
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
