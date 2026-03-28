import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/chat_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String chat_room_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 2) {
      throw ApiException.badRequest('Missing chat_room_id in URL path.');
    }
    final chatRoomId = segments[segments.length - 1];

    if (request.method == HttpMethod.get) {
      final room = await chatService.getChatRoom(
        idToken: idToken,
        chatRoomId: chatRoomId,
        role: role,
      );
      return Response.json(statusCode: HttpStatus.ok, body: room);
    }

    await chatService.deleteChatRoom(
      idToken: idToken,
      chatRoomId: chatRoomId,
      role: role,
    );
    return Response.json(
      statusCode: HttpStatus.ok,
      body: {'deleted': true, 'chatRoomId': chatRoomId},
    );
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
