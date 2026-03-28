import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/billing_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String user_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final userId = request.uri.pathSegments.last;
    if (userId.trim().isEmpty) {
      throw ApiException.badRequest('Missing user_id in URL path.');
    }

    if (request.method == HttpMethod.get) {
      final result = await billingService.getPendingTransaction(
        idToken: idToken,
        userId: userId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final result = await billingService.updatePendingTransaction(
      idToken: idToken,
      userId: userId,
      payload: body,
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
