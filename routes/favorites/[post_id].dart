import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/relationship_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String post_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.post &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final segments = request.uri.pathSegments;
    if (segments.length < 2) {
      throw ApiException.badRequest('Missing post_id in URL path.');
    }
    final postId = segments.last;

    if (request.method == HttpMethod.get) {
      final result = await relationshipService.getFavorite(
        idToken: idToken,
        postId: postId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    if (request.method == HttpMethod.post) {
      final body = await request.json();
      final payload = body is Map<String, dynamic> ? body : <String, dynamic>{};
      final result = await relationshipService.setFavorite(
        idToken: idToken,
        postId: postId,
        payload: payload,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final result = await relationshipService.deleteFavorite(
      idToken: idToken,
      postId: postId,
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
