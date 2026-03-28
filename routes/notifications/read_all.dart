import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/notification_parity_service.dart';
import 'package:workpalbackend/src/services/notification_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final role = request.uri.queryParameters['role']?.trim();
    final schema = request.uri.queryParameters['schema']?.trim();
    final targetUserId = request.uri.queryParameters['targetUserId'];
    final adminDocId = request.uri.queryParameters['adminDocId'] ?? 'Admin';
    if ((role == null || role.isEmpty) && (schema == null || schema.isEmpty)) {
      throw ApiException.badRequest(
        'Provide role=customer|artisan or schema=wp|legacy|admin|items|flat.',
      );
    }

    final idToken = requireBearerToken(request);
    final result = schema != null && schema.isNotEmpty
        ? await notificationParityService.markAllAsRead(
            idToken: idToken,
            schema: schema,
            targetUserId: targetUserId,
            adminDocId: adminDocId,
          )
        : await notificationService.markAllAsRead(
            role: role!,
            idToken: idToken,
          );
    return Response.json(statusCode: HttpStatus.ok, body: result);
  } on ApiException catch (e) {
    return Response.json(
      statusCode: e.statusCode,
      body: {'error': e.message},
    );
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}
