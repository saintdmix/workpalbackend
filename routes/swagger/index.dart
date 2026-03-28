import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405);
  }

  final origin = context.request.uri.origin.isEmpty
      ? 'http://localhost:8080'
      : context.request.uri.origin;
  final openApiUrl = '$origin/swagger/openapi';

  const htmlStart = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Workpal API Docs</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
    <style>
      html, body { margin: 0; padding: 0; }
      body { background: #f6f8fb; }
      .topbar { display: none; }
    </style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: "''';
  const htmlEnd = '''",
        dom_id: '#swagger-ui',
        deepLinking: true,
        docExpansion: 'none',
        defaultModelsExpandDepth: 1,
        displayRequestDuration: true,
        persistAuthorization: true
      });
    </script>
  </body>
</html>
''';

  return Response(
    body: '$htmlStart$openApiUrl$htmlEnd',
    headers: <String, Object>{
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}
