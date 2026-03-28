import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/chat_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String user_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.post &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final userId = request.uri.pathSegments.last;

    if (request.method == HttpMethod.get) {
      final result = await chatService.getBlockedStatus(
        idToken: idToken,
        otherId: userId,
        role: role,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final result = await chatService.setBlockedUser(
      idToken: idToken,
      otherId: userId,
      role: role,
      blocked: request.method == HttpMethod.post,
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
