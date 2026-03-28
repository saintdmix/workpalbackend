import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/services/vendor_discovery_service.dart';
import 'package:workpalbackend/src/utils/request_auth.dart';

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  if (request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final idToken = requireBearerToken(request);
    final query = request.uri.queryParameters;

    final limit = int.tryParse(query['limit'] ?? '') ?? 50;
    final pageToken = query['pageToken'];
    final location = query['location'];
    final latitude = double.tryParse(query['latitude'] ?? '');
    final longitude = double.tryParse(query['longitude'] ?? '');
    final radiusKm = double.tryParse(query['radiusKm'] ?? '') ?? 10;
    final skills = query['skills'] ?? query['searchBySkills'];
    final name = query['name'];
    final premium = _parseBool(query['premium']);

    final result = await vendorDiscoveryService.listVendors(
      idToken: idToken,
      limit: limit,
      pageToken: pageToken,
      location: location,
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      skills: skills,
      name: name,
      premium: premium,
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

bool? _parseBool(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}
