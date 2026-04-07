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
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      final pageToken = request.uri.queryParameters['pageToken'];
      final status = request.uri.queryParameters['status'];
      final customerId = request.uri.queryParameters['customerId'];
      final category = request.uri.queryParameters['category'];
      final search = request.uri.queryParameters['search'];
      final mine = _parseBool(request.uri.queryParameters['mine']);

      final result = await hiringService.listJobs(
        idToken: idToken,
        role: role,
        limit: limit,
        pageToken: pageToken,
        status: status,
        customerId: customerId,
        category: category,
        search: search,
        mine: mine,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final contentType = request.headers[HttpHeaders.contentTypeHeader] ?? '';
    final Map<String, dynamic> payload;
    final List<String> uploadedImageUrls;

    if (contentType.contains('multipart/form-data')) {
      final formData = await request.formData();
      final fields = <String, dynamic>{};
      final imageUrls = <String>[];

      // Parse all text fields.
      for (final entry in formData.fields.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value.isEmpty) {
          fields[key] = value;
        } else if (value.startsWith('[') || value.startsWith('{')) {
          fields[key] = value;
        } else if (value == 'true') {
          fields[key] = true;
        } else if (value == 'false') {
          fields[key] = false;
        } else {
          final asNum = num.tryParse(value);
          fields[key] = asNum ?? value;
        }
      }

      // Upload each file under the refImages / projectImageUrls key.
      for (final entry in formData.files.entries) {
        if (entry.key == 'refImages' ||
            entry.key == 'projectImageUrls' ||
            entry.key == 'mediaImages') {
          final file = entry.value;
          final bytes = await file.readAsBytes();
          final uploaded = await mediaUploadService.uploadBytesForPath(
            idToken: idToken,
            bytes: bytes,
            folder: 'job_images',
            defaultNamePrefix: 'job',
            fileName: file.name,
            contentType: file.contentType.mimeType,
          );
          imageUrls.add('${uploaded['downloadUrl']}');
        }
      }

      uploadedImageUrls = imageUrls;
      payload = fields;
    } else {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      payload = body;
      uploadedImageUrls = const [];
    }

    // Merge uploaded file URLs into refImages.
    final mergedPayload = <String, dynamic>{
      ...payload,
      if (uploadedImageUrls.isNotEmpty)
        'refImages': <String>[
          ..._readList(payload['refImages']),
          ..._readList(payload['projectImageUrls']),
          ...uploadedImageUrls,
        ],
    };

    final created = await hiringService.createJobPost(
      idToken: idToken,
      role: role,
      payload: mergedPayload,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}

List<String> _readList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}
