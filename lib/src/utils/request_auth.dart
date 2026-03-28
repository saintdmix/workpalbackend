import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';

String requireBearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null || header.trim().isEmpty) {
    throw ApiException.unauthorized(
      'Missing Authorization header. Expected Bearer token.',
    );
  }

  final parts = header.split(' ');
  if (parts.length != 2 || parts.first.toLowerCase() != 'bearer') {
    throw ApiException.unauthorized(
      'Invalid Authorization header. Expected Bearer token.',
    );
  }

  final token = parts[1].trim();
  if (token.isEmpty) {
    throw ApiException.unauthorized('Bearer token is empty.');
  }
  return token;
}

