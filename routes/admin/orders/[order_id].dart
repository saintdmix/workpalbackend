import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/nri_legacy_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String orderId) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.put &&
      request.method != HttpMethod.patch &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  try {
    final idToken = requireBearerToken(request);
    if (request.method == HttpMethod.get) {
      final result = await nriLegacyService.getAdminOrder(
        idToken: idToken,
        orderId: orderId,
      );
      if (result == null) {
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'Order not found.'},
        );
      }
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    if (request.method == HttpMethod.delete) {
      await nriLegacyService.deleteAdminOrder(
        idToken: idToken,
        orderId: orderId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: {'deleted': true});
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final result = await nriLegacyService.upsertAdminOrder(
      idToken: idToken,
      orderId: orderId,
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
