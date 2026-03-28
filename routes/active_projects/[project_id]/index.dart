import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/hiring_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String project_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.patch &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 2) {
      throw ApiException.badRequest('Missing project_id in URL path.');
    }
    final projectId = segments.last;

    if (request.method == HttpMethod.get) {
      final result = await hiringService.getActiveProject(
        idToken: idToken,
        role: role,
        projectId: projectId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    if (request.method == HttpMethod.patch) {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      final result = await hiringService.updateActiveProject(
        idToken: idToken,
        role: role,
        projectId: projectId,
        payload: body,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final result = await hiringService.deleteActiveProject(
      idToken: idToken,
      role: role,
      projectId: projectId,
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
