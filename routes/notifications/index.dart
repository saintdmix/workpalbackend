import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/notification_parity_service.dart';
import 'package:workpalbackend/src/services/notification_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get && request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final role = request.uri.queryParameters['role']?.trim();
    final schema = request.uri.queryParameters['schema']?.trim();
    final targetUserId = request.uri.queryParameters['targetUserId'];
    final adminDocId = request.uri.queryParameters['adminDocId'] ?? 'Admin';
    if (role == null || role.trim().isEmpty) {
      if (schema == null || schema.isEmpty) {
        throw ApiException.badRequest(
          'Provide role=customer|artisan or schema=wp|legacy|admin|items|flat.',
        );
      }
    }

    final idToken = requireBearerToken(request);

    if (request.method == HttpMethod.get) {
      final limit = int.tryParse(
            request.uri.queryParameters['limit'] ?? '',
          ) ??
          20;
      final unreadOnly =
          request.uri.queryParameters['unreadOnly']?.toLowerCase() == 'true';
      final pageToken = request.uri.queryParameters['pageToken'];

      if (schema != null && schema.isNotEmpty) {
        final data = await notificationParityService.listNotifications(
          idToken: idToken,
          schema: schema,
          targetUserId: targetUserId,
          adminDocId: adminDocId,
          limit: limit < 1 ? 1 : limit,
          unreadOnly: unreadOnly,
          pageToken: pageToken,
        );
        return Response.json(statusCode: HttpStatus.ok, body: data);
      }

      final data = await notificationService.listNotifications(
        role: role!,
        idToken: idToken,
        limit: limit < 1 ? 1 : limit,
        unreadOnly: unreadOnly,
      );
      return Response.json(statusCode: HttpStatus.ok, body: {'items': data});
    }

    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    if (schema != null && schema.isNotEmpty) {
      final created = await notificationParityService.createNotification(
        idToken: idToken,
        payload: body,
        schema: schema,
        targetUserId: targetUserId,
        adminDocId: adminDocId,
      );
      return Response.json(statusCode: HttpStatus.created, body: created);
    }

    final created = await notificationService.createNotification(
      role: role!,
      idToken: idToken,
      payload: body,
    );
    return Response.json(statusCode: HttpStatus.created, body: created);
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
