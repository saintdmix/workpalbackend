import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workpalbackend/src/exceptions/api_exception.dart';

class FirestoreRestClient {
  FirestoreRestClient({
    required String projectId,
    required String webApiKey,
    http.Client? httpClient,
  })  : _projectId = projectId,
        _webApiKey = webApiKey.trim(),
        _http = httpClient ?? http.Client();

  final String _projectId;
  final String _webApiKey;
  final http.Client _http;

  Future<void> setDocument({
    String? collection,
    String? collectionPath,
    required String documentId,
    required Map<String, dynamic> data,
    required String idToken,
  }) async {
    final targetCollection = _resolveCollection(
      collection: collection,
      collectionPath: collectionPath,
    );
    final uri = _documentUri(
      collectionPath: targetCollection,
      documentId: documentId,
    );
    final body = jsonEncode({'fields': _toFirestoreFields(data)});
    final headers = _headers(idToken);

    // Try PATCH first (update). If 404, the document doesn't exist yet — use POST to create it.
    var response = await _http.patch(uri, headers: headers, body: body);
    if (response.statusCode == 404) {
      response = await _http.post(
        _collectionUri(
          collectionPath: targetCollection,
          documentId: documentId,
        ),
        headers: headers,
        body: body,
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }
  }

  Future<Map<String, dynamic>?> getDocument({
    String? collection,
    String? collectionPath,
    required String documentId,
    required String idToken,
  }) async {
    final targetCollection = _resolveCollection(
      collection: collection,
      collectionPath: collectionPath,
    );
    final response = await _http.get(
      _documentUri(collectionPath: targetCollection, documentId: documentId),
      headers: _headers(idToken),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }

    final doc = _decodeObject(response.body);
    return _fromFirestoreDocument(doc);
  }

  Future<Map<String, dynamic>> createDocument({
    required String collectionPath,
    required String idToken,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    final response = await _http.post(
      _collectionUri(
        collectionPath: collectionPath,
        documentId: documentId,
      ),
      headers: _headers(idToken),
      body: jsonEncode({'fields': _toFirestoreFields(data)}),
    );

    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }

    return _fromFirestoreDocumentWithId(_decodeObject(response.body));
  }

  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionPath,
    required String idToken,
    int pageSize = 20,
    String? orderBy,
  }) async {
    final page = await listDocumentsPage(
      collectionPath: collectionPath,
      idToken: idToken,
      pageSize: pageSize,
      orderBy: orderBy,
    );
    return page.documents;
  }

  Future<FirestoreListPage> listDocumentsPage({
    required String collectionPath,
    required String idToken,
    int pageSize = 20,
    String? orderBy,
    String? pageToken,
  }) async {
    final response = await _http.get(
      _collectionUri(
        collectionPath: collectionPath,
        pageSize: pageSize < 1 ? 1 : pageSize,
        orderBy: orderBy,
        pageToken: pageToken,
      ),
      headers: _headers(idToken),
    );

    if (response.statusCode == 404) {
      return const FirestoreListPage(documents: <Map<String, dynamic>>[]);
    }
    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }

    final decoded = _decodeObject(response.body);
    final documents = decoded['documents'];
    if (documents is! List) {
      return FirestoreListPage(
        documents: const <Map<String, dynamic>>[],
        nextPageToken: _readNextPageToken(decoded),
      );
    }

    final result = <Map<String, dynamic>>[];
    for (final item in documents) {
      if (item is Map<String, dynamic>) {
        result.add(_fromFirestoreDocumentWithId(item));
      } else if (item is Map) {
        result.add(_fromFirestoreDocumentWithId(Map<String, dynamic>.from(item)));
      }
    }

    return FirestoreListPage(
      documents: result,
      nextPageToken: _readNextPageToken(decoded),
    );
  }

  Future<void> deleteDocument({
    required String collectionPath,
    required String documentId,
    required String idToken,
  }) async {
    final response = await _http.delete(
      _documentUri(collectionPath: collectionPath, documentId: documentId),
      headers: _headers(idToken),
    );

    if (response.statusCode == 404) return;
    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }
  }

  Future<String?> findDocumentIdByField({
    required String collection,
    required String field,
    required Object value,
    required String idToken,
    int limit = 1,
  }) async {
    final response = await _http.post(
      _runQueryUri(),
      headers: _headers(idToken),
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collection},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': _toFirestoreValue(value),
            },
          },
          'limit': limit,
        },
      }),
    );

    if (response.statusCode >= 400) {
      throw ApiException.server(_readFirebaseError(response.body));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw ApiException.server('Unexpected Firestore query response.');
    }

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final document = item['document'];
      if (document is! Map<String, dynamic>) continue;
      final name = document['name']?.toString();
      if (name == null || name.isEmpty) continue;
      return name.split('/').last;
    }
    return null;
  }

  Map<String, String> _headers(String idToken) {
    return {
      'content-type': 'application/json',
      'authorization': 'Bearer $idToken',
    };
  }

  Uri _documentUri({
    required String collectionPath,
    required String documentId,
  }) {
    final encodedCollection = _encodePath(collectionPath);
    final base = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/'
      'databases/(default)/documents/$encodedCollection/'
      '${Uri.encodeComponent(documentId)}',
    );
    return _appendApiKey(base);
  }

  Uri _collectionUri({
    required String collectionPath,
    String? documentId,
    int? pageSize,
    String? orderBy,
    String? pageToken,
  }) {
    final encodedCollection = _encodePath(collectionPath);
    final base = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/'
      'databases/(default)/documents/$encodedCollection',
    );

    final query = <String, String>{};
    if (documentId != null && documentId.trim().isNotEmpty) {
      query['documentId'] = documentId.trim();
    }
    if (pageSize != null && pageSize > 0) {
      query['pageSize'] = pageSize.toString();
    }
    if (orderBy != null && orderBy.trim().isNotEmpty) {
      query['orderBy'] = orderBy.trim();
    }
    if (pageToken != null && pageToken.trim().isNotEmpty) {
      query['pageToken'] = pageToken.trim();
    }

    final withParams =
        query.isEmpty ? base : base.replace(queryParameters: query);
    return _appendApiKey(withParams);
  }

  Uri _runQueryUri() {
    final base = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/'
      'databases/(default)/documents:runQuery',
    );
    return _appendApiKey(base);
  }

  Uri _appendApiKey(Uri uri) {
    if (_webApiKey.isEmpty) return uri;
    final params = Map<String, String>.from(uri.queryParameters);
    params['key'] = _webApiKey;
    return uri.replace(queryParameters: params);
  }

  String _readFirebaseError(String body) {
    try {
      final decoded = _decodeObject(body);
      final message =
          (decoded['error'] as Map<String, dynamic>?)?['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    return 'Firestore request failed.';
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.server('Unexpected JSON response.');
    }
    return decoded;
  }

  Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _toFirestoreValue(value)));
  }

  Map<String, dynamic> _toFirestoreValue(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map(_toFirestoreValue).toList(),
        },
      };
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {
          'fields': value.map((k, v) => MapEntry(k, _toFirestoreValue(v))),
        },
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': value.map(
            (k, v) => MapEntry(k.toString(), _toFirestoreValue(v)),
          ),
        },
      };
    }
    if (value is num) return {'doubleValue': value.toDouble()};
    return {'stringValue': value.toString()};
  }

  Map<String, dynamic> _fromFirestoreDocument(Map<String, dynamic> document) {
    final fields = document['fields'];
    if (fields is! Map<String, dynamic>) return {};
    return fields.map((key, value) {
      if (value is Map<String, dynamic>) {
        return MapEntry(key, _fromFirestoreValue(value));
      }
      if (value is Map) {
        return MapEntry(key, _fromFirestoreValue(Map<String, dynamic>.from(value)));
      }
      return MapEntry(key, value);
    });
  }

  Map<String, dynamic> _fromFirestoreDocumentWithId(
    Map<String, dynamic> document,
  ) {
    final data = _fromFirestoreDocument(document);
    final name = document['name']?.toString() ?? '';
    final id = name.isEmpty ? '' : name.split('/').last;
    return <String, dynamic>{
      'id': id,
      ...data,
    };
  }

  String _resolveCollection({
    String? collection,
    String? collectionPath,
  }) {
    final resolved = (collectionPath ?? collection ?? '').trim();
    if (resolved.isEmpty) {
      throw ApiException.badRequest('collectionPath is required.');
    }
    return resolved;
  }

  String _encodePath(String path) {
    return path
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }

  String? _readNextPageToken(Map<String, dynamic> decoded) {
    final token = decoded['nextPageToken']?.toString().trim() ?? '';
    if (token.isEmpty) return null;
    return token;
  }

  dynamic _fromFirestoreValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue']?.toString() ?? '') ?? 0;
    }
    if (value.containsKey('doubleValue')) {
      final raw = value['doubleValue'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0.0;
    }
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('geoPointValue')) {
      final geo = value['geoPointValue'];
      if (geo is Map<String, dynamic>) {
        return <String, dynamic>{
          'latitude': geo['latitude'],
          'longitude': geo['longitude'],
        };
      }
      if (geo is Map) {
        final casted = Map<String, dynamic>.from(geo);
        return <String, dynamic>{
          'latitude': casted['latitude'],
          'longitude': casted['longitude'],
        };
      }
      return null;
    }
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('arrayValue')) {
      final values = (value['arrayValue'] as Map<String, dynamic>?)?['values'];
      if (values is! List) return <dynamic>[];
      final out = <dynamic>[];
      for (final item in values) {
        if (item is Map<String, dynamic>) {
          out.add(_fromFirestoreValue(item));
        } else if (item is Map) {
          out.add(_fromFirestoreValue(Map<String, dynamic>.from(item)));
        }
      }
      return out;
    }
    if (value.containsKey('mapValue')) {
      final fields = (value['mapValue'] as Map<String, dynamic>?)?['fields'];
      if (fields is! Map<String, dynamic>) return <String, dynamic>{};
      return fields.map((k, v) {
        if (v is Map<String, dynamic>) {
          return MapEntry(k, _fromFirestoreValue(v));
        }
        if (v is Map) {
          return MapEntry(k, _fromFirestoreValue(Map<String, dynamic>.from(v)));
        }
        return MapEntry(k, v);
      });
    }
    return null;
  }
}

class FirestoreListPage {
  const FirestoreListPage({
    required this.documents,
    this.nextPageToken,
  });

  final List<Map<String, dynamic>> documents;
  final String? nextPageToken;
}
