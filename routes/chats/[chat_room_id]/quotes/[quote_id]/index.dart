import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/hiring_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String chat_room_id, String quote_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 4) {
      throw ApiException.badRequest(
        'Missing chat_room_id or quote_id in URL path.',
      );
    }
    final chatRoomId = segments[segments.length - 3];
    final quoteId = segments.last;

    if (request.method == HttpMethod.get) {
      final result = await hiringService.getQuote(
        idToken: idToken,
        role: role,
        quoteId: quoteId,
        chatRoomId: chatRoomId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final status = '${body['status'] ?? ''}'.trim();
    if (status.isEmpty) {
      throw ApiException.badRequest('status is required.');
    }

    final result = await hiringService.updateQuoteStatus(
      idToken: idToken,
      role: role,
      quoteId: quoteId,
      chatRoomId: chatRoomId,
      status: status,
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
