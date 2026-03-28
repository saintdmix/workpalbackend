import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/chat_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];

    if (request.method == HttpMethod.get) {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      final pageToken = request.uri.queryParameters['pageToken'];
      final search = request.uri.queryParameters['search'];
      final result = await chatService.listChatRooms(
        idToken: idToken,
        role: role,
        limit: limit,
        pageToken: pageToken,
        search: search,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final chatRoomId = '${body['chatRoomId'] ?? ''}';
    final otherId = '${body['otherId'] ?? ''}';
    final created = await chatService.upsertChatRoom(
      idToken: idToken,
      chatRoomId: chatRoomId,
      otherId: otherId,
      role: role,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.ok, body: created);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
