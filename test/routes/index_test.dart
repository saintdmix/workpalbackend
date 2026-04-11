import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../routes/index.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  group('GET /', () {
    test('responds with service status JSON.', () async {
      final context = _MockRequestContext();
      final response = route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.ok));

      final raw = await response.body();
      final decoded = jsonDecode(raw);
      expect(decoded, isA<Map>());
      final json = Map<String, dynamic>.from(decoded as Map);
      expect(json['status'], equals('ok'));
      expect(json['service'], isNotNull);
    });
  });
}
