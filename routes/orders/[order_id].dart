import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/commerce_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String order_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get &&
      request.method != HttpMethod.patch &&
      request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final orderId = request.uri.pathSegments.last;
    if (orderId.trim().isEmpty) {
      throw ApiException.badRequest('Missing order_id in URL path.');
    }

    if (request.method == HttpMethod.get) {
      final result = await commerceService.getOrder(
        idToken: idToken,
        orderId: orderId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    if (request.method == HttpMethod.patch) {
      final body = await request.json();
      if (body is! Map<String, dynamic>) {
        throw ApiException.badRequest('Request body must be a JSON object.');
      }
      final result = await commerceService.updateOrder(
        idToken: idToken,
        orderId: orderId,
        payload: body,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final result = await commerceService.deleteOrder(
      idToken: idToken,
      orderId: orderId,
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
