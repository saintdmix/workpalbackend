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
      final storyIdsParam = request.uri.queryParameters['storyIds'] ?? '';
      final storyIds = storyIdsParam
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      final viewed = await storiesService.fetchViewedStoryIds(
        idToken: idToken,
        storyIds: storyIds,
      );
      return Response.json(
        statusCode: HttpStatus.ok,
        body: {'viewedStoryIds': viewed},
      );
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final storyId = '${body['storyId'] ?? ''}'.trim();
    if (storyId.isEmpty) {
      throw ApiException.badRequest('storyId is required.');
    }

    final result = await storiesService.markStoryViewed(
      idToken: idToken,
      storyId: storyId,
    );
    return Response.json(statusCode: HttpStatus.ok, body: result);
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
