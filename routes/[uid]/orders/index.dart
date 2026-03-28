import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/nri_legacy_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String uid) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  try {
    final idToken = requireBearerToken(request);
    final isAdminNode = uid.trim().toLowerCase() == 'admin';

    if (request.method == HttpMethod.get) {
      final result = isAdminNode
          ? await nriLegacyService.listAdminOrders(
              idToken: idToken,
              status: request.uri.queryParameters['status'],
            )
          : await nriLegacyService.listUserOrders(
              idToken: idToken,
              uid: uid,
              status: request.uri.queryParameters['status'],
            );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final result = isAdminNode
        ? await nriLegacyService.createAdminOrder(
            idToken: idToken,
            payload: body,
          )
        : await nriLegacyService.createUserOrder(
            idToken: idToken,
            uid: uid,
            payload: body,
          );
    return Response.json(statusCode: HttpStatus.created, body: result);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
