// Place in: lib/src/exceptions/api_exception.dart
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  factory ApiException.badRequest(String message) => ApiException(400, message);
  factory ApiException.unauthorized(String message) => ApiException(401, message);
  factory ApiException.forbidden(String message) => ApiException(403, message);
  factory ApiException.conflict(String message) => ApiException(409, message);
  factory ApiException.notFound(String message) => ApiException(404, message);
  factory ApiException.server(String message) => ApiException(500, message);
  factory ApiException.internal(String message) => ApiException(500, message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
