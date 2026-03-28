import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/relationship_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String vendor_id) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];
    final segments = request.uri.pathSegments;
    if (segments.length < 3) {
      throw ApiException.badRequest('Missing vendor_id in URL path.');
    }
    final vendorId = segments.last;

    if (request.method == HttpMethod.get) {
      final result = await relationshipService.getVendorRelationship(
        idToken: idToken,
        role: role,
        vendorId: vendorId,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    final payload = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final follow = _parseBool(payload['follow']);

    final result = await relationshipService.setVendorFollow(
      idToken: idToken,
      role: role,
      vendorId: vendorId,
      follow: follow,
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

bool? _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}
