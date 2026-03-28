import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/promotion_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    if (request.method == HttpMethod.get) {
      final activeOnly =
          request.uri.queryParameters['activeOnly']?.toLowerCase() != 'false';
      final result = await promotionService.listPromotedPosts(
        idToken: idToken,
        artisanId: request.uri.queryParameters['artisanId'],
        activeOnly: activeOnly,
        limit: int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 30,
        pageToken: request.uri.queryParameters['pageToken'],
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final created = await promotionService.createPromotedPost(
      idToken: idToken,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
