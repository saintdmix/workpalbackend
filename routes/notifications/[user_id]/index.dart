import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/notification_parity_service.dart';
import 'package:workpalbackend/src/services/notification_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context, String userId) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final targetUserId = userId.trim();
    if (targetUserId.isEmpty) {
      throw ApiException.badRequest('user_id is required in the URL path.');
    }

    final role = request.uri.queryParameters['role']?.trim();
    final schema = request.uri.queryParameters['schema']?.trim();
    final adminDocId = request.uri.queryParameters['adminDocId'] ?? 'Admin';
    if ((role == null || role.isEmpty) && (schema == null || schema.isEmpty)) {
      throw ApiException.badRequest(
        'Provide role=customer|artisan or schema=wp|legacy|admin|items|flat.',
      );
    }

    final idToken = requireBearerToken(request);
    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final created = schema != null && schema.isNotEmpty
        ? await notificationParityService.createNotification(
            idToken: idToken,
            payload: body,
            schema: schema,
            targetUserId: targetUserId,
            adminDocId: adminDocId,
          )
        : await notificationService.createNotification(
            role: role!,
            idToken: idToken,
            payload: body,
            targetUserId: targetUserId,
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
