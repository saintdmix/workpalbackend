import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:workpalbackend/src/docs/openapi_spec.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final spec = buildOpenApiSpec(requestUri: context.request.uri);
  return Response(
    body: jsonEncode(spec),
    headers: <String, Object>{
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}
