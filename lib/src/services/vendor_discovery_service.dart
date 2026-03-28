import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final vendorDiscoveryService = VendorDiscoveryService();

class VendorDiscoveryService {
  VendorDiscoveryService({
    FirebaseAuthRestClient? authClient,
    FirestoreRestClient? firestoreClient,
  })  : _authClient = authClient ??
            FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
        _firestoreClient = firestoreClient ??
            FirestoreRestClient(
              projectId: AppEnv.firebaseProjectId,
              webApiKey: AppEnv.firebaseWebApiKey,
            );

  final FirebaseAuthRestClient _authClient;
  final FirestoreRestClient _firestoreClient;

  Future<Map<String, dynamic>> listVendors({
    required String idToken,
    int limit = 50,
    String? pageToken,
    String? location,
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    String? skills,
    String? name,
    bool? premium,
  }) async {
    await _resolveUid(idToken);

    final safeLimit = limit.clamp(1, 200).toInt();
    final safeRadius = radiusKm <= 0 ? 10.0 : radiusKm;
    final locationText = location?.trim().toLowerCase();
    final nameText = name?.trim().toLowerCase();
    final skillTokens = _splitQueryTokens(skills);

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'vendors',
      idToken: idToken,
      pageSize: max(safeLimit * 3, 60).toInt(),
      orderBy: 'rating desc',
      pageToken: pageToken,
    );

    final filtered = <Map<String, dynamic>>[];
    final parsedFromLocation = _parseLatLngFromLocation(location);
    final targetLat = latitude ?? parsedFromLocation?.latitude;
    final targetLng = longitude ?? parsedFromLocation?.longitude;

    for (final vendor in page.documents) {
      final item = <String, dynamic>{...vendor};
      final nameValue = _text(item['name']) ?? _text(item['username']) ?? '';
      final titleValue = _text(item['title']) ?? '';
      final skillsList = _readStringList(item['skills']);
      final locationAddress = _text(item['locationAddress']) ??
          _text(item['address']) ??
          _text(item['city']) ??
          '';
      final status = _text(item['subscriptionStatus']) ?? '';
      final isPremium = _isPremiumVendor(item);

      if (premium != null && isPremium != premium) continue;

      if (nameText != null && nameText.isNotEmpty) {
        final inName = nameValue.toLowerCase().contains(nameText) ||
            titleValue.toLowerCase().contains(nameText);
        if (!inName) continue;
      }

      if (skillTokens.isNotEmpty) {
        final haystack = skillsList.map((e) => e.toLowerCase()).toList();
        final matchesAny = skillTokens
            .any((token) => haystack.any((skill) => skill.contains(token)));
        if (!matchesAny) continue;
      }

      if (locationText != null &&
          locationText.isNotEmpty &&
          targetLat == null &&
          targetLng == null) {
        final inAddress = locationAddress.toLowerCase().contains(locationText);
        if (!inAddress) continue;
      }

      double? distanceKm;
      if (targetLat != null && targetLng != null) {
        final point = _readGeoPoint(item['location']);
        if (point == null) continue;
        distanceKm = _haversineKm(
          targetLat,
          targetLng,
          point.latitude,
          point.longitude,
        );
        if (distanceKm > safeRadius) continue;
      }

      filtered.add(<String, dynamic>{
        ...item,
        'isPremium': isPremium,
        'subscriptionStatus': status,
        if (distanceKm != null)
          'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
      });
    }

    if (targetLat != null && targetLng != null) {
      filtered.sort((a, b) {
        final da = (a['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        final db = (b['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        return da.compareTo(db);
      });
    }

    return <String, dynamic>{
      'items': filtered.take(safeLimit).toList(),
      'count': min(filtered.length, safeLimit).toInt(),
      'query': <String, dynamic>{
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
        if (targetLat != null) 'latitude': targetLat,
        if (targetLng != null) 'longitude': targetLng,
        'radiusKm': safeRadius,
        if (skills != null && skills.trim().isNotEmpty) 'skills': skills.trim(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (premium != null) 'premium': premium,
      },
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  List<String> _splitQueryTokens(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>[];
    return raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _text(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        out.add(item.trim());
      }
    }
    return out;
  }

  bool _isPremiumVendor(Map<String, dynamic> vendor) {
    if (vendor['premium'] == true) return true;
    if (vendor['isPremium'] == true) return true;
    final status = (_text(vendor['subscriptionStatus']) ?? '').toLowerCase();
    return status == 'active' || status == 'premium' || status == 'pro';
  }

  _LatLng? _parseLatLngFromLocation(String? location) {
    if (location == null || location.trim().isEmpty) return null;
    final parts = location.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return _LatLng(latitude: lat, longitude: lng);
  }

  _LatLng? _readGeoPoint(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final lat = _asDouble(raw['latitude']) ?? _asDouble(raw['_latitude']);
      final lng = _asDouble(raw['longitude']) ?? _asDouble(raw['_longitude']);
      if (lat != null && lng != null) {
        return _LatLng(latitude: lat, longitude: lng);
      }
    } else if (raw is Map) {
      return _readGeoPoint(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * pow(sin(dLon / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * (pi / 180.0);
}

class _LatLng {
  const _LatLng({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}
