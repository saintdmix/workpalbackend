import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/billing_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String payment_type, String transaction_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest(
          'Missing payment_type or transaction_id in URL path.');
    }
    final paymentType = segments[segments.length - 2];
    final transactionId = segments.last;

    if (request.method == HttpMethod.get) {
      final result = await billingService.getTransactionWp(
        idToken: idToken,
        paymentType: paymentType,
        transactionId: transactionId,
        userId: request.uri.queryParameters['userId'],
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final result = await billingService.updateTransactionWp(
      idToken: idToken,
      paymentType: paymentType,
      transactionId: transactionId,
      userId: request.uri.queryParameters['userId'],
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
