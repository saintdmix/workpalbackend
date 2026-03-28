import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/workfeed_engagement_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String post_id) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing post id in URL path.');
    }
    final postId = segments[segments.length - 2];

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final result = await workfeedEngagementService.reportPost(
      idToken: idToken,
      postId: postId,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.created, body: result);
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
