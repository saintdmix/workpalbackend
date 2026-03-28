import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/workfeed_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String post_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final segments = request.uri.pathSegments;
    final postId = segments.isEmpty ? '' : segments.last;
    if (postId.trim().isEmpty) {
      throw ApiException.badRequest('Missing post id in URL path.');
    }

    if (request.method == HttpMethod.get) {
      final post = await workfeedService.getWorkfeed(
        idToken: idToken,
        postId: postId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: post);
    }

    final deleted = await workfeedService.deleteWorkfeed(
      idToken: idToken,
      postId: postId,
    );
    return Response.json(statusCode: HttpStatus.ok, body: deleted);
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
