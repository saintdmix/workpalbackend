import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/hiring_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String job_id) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing job_id in URL path.');
    }
    final jobId = segments[segments.length - 2];

    final body = await request.json();
    final payload = body is Map<String, dynamic> ? body : <String, dynamic>{};

    final result = await hiringService.applyToJob(
      idToken: idToken,
      role: role,
      jobId: jobId,
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
