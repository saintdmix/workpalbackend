import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/legacy_profile_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    if (request.method == HttpMethod.get) {
      final result = await legacyProfileService.getLegacyProfile(
        idToken: idToken,
        userId: request.uri.queryParameters['userId'],
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final updated = await legacyProfileService.upsertLegacyProfile(
      idToken: idToken,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.ok, body: updated);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
