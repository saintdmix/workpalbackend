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
      final result = await chatService.getPinnedChats(
        idToken: idToken,
        role: role,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final chatRoomId = '${body['chatRoomId'] ?? ''}'.trim();
    if (chatRoomId.isEmpty) {
      throw ApiException.badRequest('chatRoomId is required.');
    }

    var pinned = false;
    if (body.containsKey('pinned')) {
      pinned = body['pinned'] == true;
    } else {
      final current =
          await chatService.getPinnedChats(idToken: idToken, role: role);
      final currentList =
          (current['pinnedChats'] as List?)?.whereType<String>().toList() ??
              <String>[];
      pinned = !currentList.contains(chatRoomId);
    }

    final result = await chatService.setPinnedChat(
      idToken: idToken,
      chatRoomId: chatRoomId,
      pinned: pinned,
      role: role,
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
