import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/stories_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);

    if (request.method == HttpMethod.get) {
      final artisanId = request.uri.queryParameters['artisanId'];
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 50;
      final hours =
          int.tryParse(request.uri.queryParameters['withinHours'] ?? '') ?? 48;
      final latitude =
          _parseDoubleParam(request.uri.queryParameters['latitude'], 'latitude');
      final longitude = _parseDoubleParam(
        request.uri.queryParameters['longitude'],
        'longitude',
      );

      if ((latitude == null) != (longitude == null)) {
        throw ApiException.badRequest(
          'latitude and longitude are required together.',
        );
      }

      final items = await storiesService.listStories(
        idToken: idToken,
        artisanId: artisanId,
        limit: limit,
        withinHours: hours,
        latitude: latitude,
        longitude: longitude,
      );
      return Response.json(statusCode: HttpStatus.ok, body: {'items': items});
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final created = await storiesService.createStory(
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

double? _parseDoubleParam(String? value, String name) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = double.tryParse(value.trim());
  if (parsed == null) {
    throw ApiException.badRequest('$name must be a valid number.');
  }
  return parsed;
}
