import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/profile_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.put && request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final role = request.uri.queryParameters['role'];
    if (role == null || role.trim().isEmpty) {
      throw ApiException.badRequest(
        'Query parameter role is required (customer|artisan).',
      );
    }

    final idToken = requireBearerToken(request);
    final body = await request.json();
    if (body is! Map<String, dynamic>) {
      throw ApiException.badRequest('Request body must be a JSON object.');
    }

    final latitude = _readCoordinate(
      body,
      primaryKey: 'latitude',
      aliasKey: 'lat',
    );
    final longitude = _readCoordinate(
      body,
      primaryKey: 'longitude',
      aliasKey: 'lng',
    );

    if (latitude == null || longitude == null) {
      throw ApiException.badRequest(
        'latitude and longitude are required. You can also send lat and lng.',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw ApiException.badRequest('latitude must be between -90 and 90.');
    }
    if (longitude < -180 || longitude > 180) {
      throw ApiException.badRequest('longitude must be between -180 and 180.');
    }

    final updates = <String, dynamic>{
      'lat': latitude,
      'lng': longitude,
      'latitude': latitude,
      'longitude': longitude,
      'location': <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      },
    };

    final address = _optionalString(body, 'address');
    if (address != null) {
      updates['address'] = address;
    }

    final locationAddress =
        _optionalString(body, 'locationAddress') ??
        _optionalString(body, 'location');
    if (locationAddress != null) {
      updates['locationAddress'] = locationAddress;
    }

    final updated = await profileService.updateProfile(
      role: role,
      idToken: idToken,
      updates: updates,
    );

    return Response.json(
      body: <String, dynamic>{
        'message': 'Location updated successfully.',
        'profile': updated,
      },
    );
  } on ApiException catch (e) {
    return Response.json(statusCode: e.statusCode, body: {'error': e.message});
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected server error.'},
    );
  }
}

double? _readCoordinate(
  Map<String, dynamic> body, {
  required String primaryKey,
  required String aliasKey,
}) {
  final primary = _asDouble(body[primaryKey]);
  if (primary != null) return primary;
  return _asDouble(body[aliasKey]);
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String && value.trim().isNotEmpty) {
    return double.tryParse(value.trim());
  }
  return null;
}

String? _optionalString(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
