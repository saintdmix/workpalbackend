import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/vendor_profile_content_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String vendor_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing vendor_id in URL path.');
    }
    final vendorId = segments[segments.length - 2];
    final limit =
        int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 100;
    final pageToken = request.uri.queryParameters['pageToken'];

    final result = await vendorProfileContentService.listVendorPortfolio(
      idToken: idToken,
      vendorId: vendorId,
      limit: limit,
      pageToken: pageToken,
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
