import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/auth_service.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final email = '${body['email'] ?? ''}'.trim();
    if (email.isEmpty) {
      throw ApiException.badRequest('email is required.');
    }
    final result = await authService.forgotPassword(email: email);
    return Response.json(statusCode: HttpStatus.ok, body: result);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}
