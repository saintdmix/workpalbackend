import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/auth_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(context.request);
    final result = await authService.signOut(idToken: idToken);
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
