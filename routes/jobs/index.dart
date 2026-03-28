import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/hiring_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final role = request.uri.queryParameters['role'];

    if (request.method == HttpMethod.get) {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      final pageToken = request.uri.queryParameters['pageToken'];
      final status = request.uri.queryParameters['status'];
      final customerId = request.uri.queryParameters['customerId'];
      final category = request.uri.queryParameters['category'];
      final search = request.uri.queryParameters['search'];
      final mine = _parseBool(request.uri.queryParameters['mine']);

      final result = await hiringService.listJobs(
        idToken: idToken,
        role: role,
        limit: limit,
        pageToken: pageToken,
        status: status,
        customerId: customerId,
        category: category,
        search: search,
        mine: mine,
      );
      return Response.json(statusCode: HttpStatus.ok, body: result);
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final created = await hiringService.createJobPost(
      idToken: idToken,
      role: role,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}

bool? _parseBool(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}
