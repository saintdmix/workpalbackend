import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/billing_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String payout_id) async {
  final request = context.request;
  if (request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final payoutId = request.uri.pathSegments.last;
    if (payoutId.trim().isEmpty) {
      throw ApiException.badRequest('Missing payout_id in URL path.');
    }
    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }
    final updated = await billingService.updateAdminPayout(
      idToken: idToken,
      payoutId: payoutId,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.ok, body: updated);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
