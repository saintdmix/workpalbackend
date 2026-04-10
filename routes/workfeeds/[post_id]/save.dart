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
    // Expected path: /workfeeds/{post_id}/save
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing post id in URL path.');
    }
    final postId = segments[segments.length - 2];

    final result = await workfeedEngagementService.toggleSavedPost(
      idToken: idToken,
      postId: postId,
    );
    return Response.json(statusCode: HttpStatus.ok, body: result);
  } on ApiException catch (e) {
    return Response.json(
      statusCode: e.statusCode,
      body: {'error': e.message},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error: $e'},
    );
  }
}
