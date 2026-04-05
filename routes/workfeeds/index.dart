import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
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
      final latitude =
          _parseDoubleParam(request.uri.queryParameters['latitude'], 'latitude');
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
      return Response.json(body: {
        'items': result.items,
        if (result.nextPageToken != null) 'nextPageToken': result.nextPageToken,
      });
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final created = await workfeedService.createWorkfeed(
      idToken: idToken,
      payload: body,
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
