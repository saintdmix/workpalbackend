import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';
import 'package:workpalbackend/src/services/chat_service.dart';

final hiringService = HiringService();

class HiringService {
  HiringService({
    FirebaseAuthRestClient? authClient,
    FirestoreRestClient? firestoreClient,
    ChatService? chatServiceInstance,
  })  : _authClient = authClient ??
            FirebaseAuthRestClient(webApiKey: AppEnv.firebaseWebApiKey),
        _firestoreClient = firestoreClient ??
            FirestoreRestClient(
              projectId: AppEnv.firebaseProjectId,
              webApiKey: AppEnv.firebaseWebApiKey,
            ),
        _chatService = chatServiceInstance ?? chatService;

  final FirebaseAuthRestClient _authClient;
  final FirestoreRestClient _firestoreClient;
  final ChatService _chatService;
  final Random _random = Random();

  Future<Map<String, dynamic>> listJobs({
    required String idToken,
    String? role,
    int limit = 20,
    String? pageToken,
    String? status,
    String? customerId,
    String? category,
    String? search,
    bool? mine,
    bool? applied,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final safeLimit = limit.clamp(1, 100).toInt();
    final statusFilter = status?.trim().toLowerCase();
    final categoryFilter = category?.trim().toLowerCase();
    final searchFilter = search?.trim().toLowerCase();
    final customerFilter = customerId?.trim();

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'job_posts',
      idToken: idToken,
      pageSize: max(safeLimit * 4, 80).toInt(),
      orderBy: 'timestamp desc',
      pageToken: pageToken,
    );

    final defaultMine = actor.isCustomer;
    final mineOnly = mine ?? defaultMine;
    final appliedOnly = actor.isVendor && applied == true;

    final items = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{
        ...raw,
        'id': '${raw['id'] ?? raw['jobId'] ?? ''}',
      };
      final ownerId = '${item['customerId'] ?? ''}'.trim();
      final itemStatus = _jobStatus(item);

      if (mineOnly && ownerId != actor.uid) continue;
      if (!mineOnly &&
          actor.isVendor &&
          statusFilter == null &&
          itemStatus != 'open' && itemStatus != 'review') {
        // Vendor browse defaults to open/review jobs to match feed behavior.
        // Unless they specifically look for their applied jobs.
        if (!appliedOnly) continue;
      }
      
      final applicants = _readStringList(item['applicants']);
      if (appliedOnly && !applicants.contains(actor.uid)) continue;

      if (customerFilter != null &&
          customerFilter.isNotEmpty &&
          ownerId != customerFilter) {
        continue;
      }
      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          itemStatus != statusFilter) {
        continue;
      }
      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        final itemCategory = '${item['category'] ?? ''}'.trim().toLowerCase();
        if (!itemCategory.contains(categoryFilter)) continue;
      }
      if (searchFilter != null && searchFilter.isNotEmpty) {
        final haystack = <String>[
          '${item['title'] ?? ''}',
          '${item['description'] ?? ''}',
          '${item['address'] ?? ''}',
          '${item['category'] ?? ''}',
          '${item['customerName'] ?? ''}',
        ].join(' ').toLowerCase();
        if (!haystack.contains(searchFilter)) continue;
      }
      items.add(item);
    }

    items.sort(
      (a, b) => _timestampMs(b['timestamp'], fallback: b['createdAt'])
          .compareTo(_timestampMs(a['timestamp'], fallback: a['createdAt'])),
    );

    return <String, dynamic>{
      'items': items.take(safeLimit).toList(),
      'count': min(items.length, safeLimit).toInt(),
      'mine': mineOnly,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> createJobPost({
    required String idToken,
    String? role,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    if (!actor.isCustomer) {
      throw ApiException.forbidden('Only customers can post jobs.');
    }
    final uid = actor.uid;

    final title = _requiredString(payload, 'title');
    final category = _requiredString(payload, 'category');
    final isRemote = _asBool(payload['isRemote']) ?? false;
    final address = _optionalString(payload, 'address') ?? '';

    final profile = actor.profile;

    final nowIso = _nowIso();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final jobId = _optionalString(payload, 'jobId') ?? _nextId(prefix: 'job');

    final latitude = _asDouble(payload['latitude']);
    final longitude = _asDouble(payload['longitude']);
    final normalizedLocation = _normalizeLocation(
      payload['location'],
      latitude: latitude,
      longitude: longitude,
      isRemote: isRemote,
    );

    final data = <String, dynamic>{
      'jobId': jobId,
      'customerId': uid,
      'customerName': _customerName(profile),
      'customerImage': _profileImage(profile),
      'title': title,
      'category': category,
      'description': _optionalString(payload, 'description') ?? '',
      'budgetMin': _asDouble(payload['budgetMin']) ?? 0.0,
      'budgetMax': _asDouble(payload['budgetMax']) ?? 0.0,
      'isUrgent': _asBool(payload['isUrgent']) ?? false,
      'isRemote': isRemote,
      'address': address,
      'location': normalizedLocation,
      'latitude': isRemote ? null : latitude,
      'longitude': isRemote ? null : longitude,
      'startDate':
          _parseDateTime(payload['startDate'])?.toUtc().toIso8601String(),
      'endDate': _parseDateTime(payload['endDate'])?.toUtc().toIso8601String(),
      'refImages': _readStringList(payload['projectImageUrls'] ?? payload['refImages']),
      'mediaImages': _readStringList(payload['mediaImages']),
      'requirements': _readStringList(payload['requirements']),
      'applicants': _readStringList(payload['applicants']),
      'status': _optionalString(payload, 'status')?.toLowerCase() ?? 'review',
      'assignedVendorId': '',
      'timestamp': nowIso,
      'createdAt': nowMs,
      'updatedAt': nowIso,
    };

    for (final key in const <String>[
      'city',
      'state',
      'timeline',
      'priority',
      'urgency',
      'dimensions',
      'technique',
      'equipment',
      'experience',
    ]) {
      if (payload.containsKey(key)) data[key] = payload[key];
    }

    await _firestoreClient.setDocument(
      collectionPath: 'job_posts',
      documentId: jobId,
      idToken: idToken,
      data: data,
    );

    // Mirror to posts collection so the job appears in the workfeed.
    await _firestoreClient.setDocument(
      collectionPath: 'posts',
      documentId: jobId,
      idToken: idToken,
      data: <String, dynamic>{
        ...data,
        'type': 'job',
        'artisanId': uid,
        'content': data['description'] ?? data['title'] ?? '',
        'imageUrl': data['refImages'] ?? <String>[],
        'likes': <dynamic>[],
        'isAdminPost': false,
        'timestamp': nowIso,
      },
    );

    return <String, dynamic>{'id': jobId, ...data};
  }

  Future<Map<String, dynamic>> getJobPost({
    required String idToken,
    required String jobId,
  }) async {
    await _resolveUid(idToken);
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'job_posts',
      documentId: jobId.trim(),
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Job post not found.');
    return <String, dynamic>{'id': jobId.trim(), ...doc};
  }

  Future<Map<String, dynamic>> updateJobPost({
    required String idToken,
    String? role,
    required String jobId,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final existing = await _jobOrThrow(jobId: jobId, idToken: idToken);
    
    // Only job owner or the assigned artisan can update, depending on the logic.
    // For now, job owner controls status (review -> progress -> completed)
    if ('${existing['customerId'] ?? ''}' != actor.uid) {
      throw ApiException.forbidden('Only the job owner can update this post.');
    }

    final String? nextStatus = _optionalString(payload, 'status')?.toLowerCase();
    
    // If completing the job, increment vendor's completed works
    if (nextStatus == 'completed' && '${existing['status'] ?? ''}' != 'completed') {
      final String assignedId = _optionalString(payload, 'assignedVendorId') ?? '${existing['assignedVendorId'] ?? ''}';
      if (assignedId.isNotEmpty) {
        // Find the profile and increment completed works
        final artisanDoc = await _firestoreClient.getDocument(
          collectionPath: 'artisans', documentId: assignedId, idToken: idToken
        ) ?? await _firestoreClient.getDocument(
          collectionPath: 'vendors', documentId: assignedId, idToken: idToken
        );
        if (artisanDoc != null) {
          final int currentCount = (artisanDoc['completedWorks'] as num?)?.toInt() ?? 0;
          await _firestoreClient.setDocument(
            collectionPath: artisanDoc.containsKey('isArtisan') ? 'artisans' : 'vendors',
            documentId: assignedId,
            idToken: idToken,
            data: <String, dynamic>{
              ...artisanDoc,
              'completedWorks': currentCount + 1,
            }
          );
        }
      }
    }

    final updates = _sanitizeJobUpdates(payload);
    if (updates.isEmpty) {
      throw ApiException.badRequest('No editable fields were provided.');
    }

    final merged = <String, dynamic>{
      ...existing,
      ...updates,
      'updatedAt': _nowIso(),
    };

    await _firestoreClient.setDocument(
      collectionPath: 'job_posts',
      documentId: jobId.trim(),
      idToken: idToken,
      data: merged,
    );

    return <String, dynamic>{'id': jobId.trim(), ...merged};
  }

  Future<Map<String, dynamic>> deleteJobPost({
    required String idToken,
    String? role,
    required String jobId,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final existing = await _jobOrThrow(jobId: jobId, idToken: idToken);
    if ('${existing['customerId'] ?? ''}' != actor.uid) {
      throw ApiException.forbidden('Only the job owner can delete this post.');
    }

    await _firestoreClient.deleteDocument(
      collectionPath: 'job_posts',
      documentId: jobId.trim(),
      idToken: idToken,
    );

    return <String, dynamic>{'deleted': true, 'jobId': jobId.trim()};
  }



  Future<Map<String, dynamic>> listQuotes({
    required String idToken,
    String? role,
    String? chatRoomId,
    int limit = 30,
    String? status,
    String? jobId,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final safeLimit = limit.clamp(1, 100).toInt();
    final statusFilter = status?.trim().toLowerCase();
    final jobFilter = jobId?.trim();

    final quotes = <Map<String, dynamic>>[];
    final roomId = chatRoomId?.trim() ?? '';
    if (roomId.isNotEmpty) {
      final chunk = await _quotesForRoom(
        idToken: idToken,
        role: actor.role,
        chatRoomId: roomId,
        limit: max(safeLimit * 2, 50).toInt(),
      );
      quotes.addAll(chunk);
    } else {
      final roomsResult = await _chatService.listChatRooms(
        idToken: idToken,
        role: actor.role,
        limit: max(safeLimit * 2, 20).toInt(),
      );
      final rooms = roomsResult['items'];
      if (rooms is List) {
        for (final raw in rooms) {
          final room = _mapOrNull(raw);
          if (room == null) continue;
          final rid = '${room['id'] ?? ''}'.trim();
          if (rid.isEmpty) continue;
          final chunk = await _quotesForRoom(
            idToken: idToken,
            role: actor.role,
            chatRoomId: rid,
            limit: 30,
          );
          quotes.addAll(chunk);
          if (quotes.length >= safeLimit * 3) break;
        }
      }
    }

    final filtered = <Map<String, dynamic>>[];
    for (final quote in quotes) {
      final quoteStatus = '${quote['quoteStatus'] ?? ''}'.trim().toLowerCase();
      final quoteData =
          _mapOrNull(quote['quoteData']) ?? const <String, dynamic>{};
      final quoteJobId = '${quoteData['jobId'] ?? ''}'.trim();
      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          quoteStatus != statusFilter) {
        continue;
      }
      if (jobFilter != null &&
          jobFilter.isNotEmpty &&
          quoteJobId != jobFilter) {
        continue;
      }
      filtered.add(quote);
    }

    filtered.sort(
      (a, b) =>
          _timestampMs(b['timestamp']).compareTo(_timestampMs(a['timestamp'])),
    );

    final takenItems = filtered.take(safeLimit).toList();
    
    final applicantIds = takenItems
        .map((q) => '${q['senderId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final applicants = <Map<String, dynamic>>[];
    for (final uid in applicantIds) {
      try {
        final doc = await _firestoreClient.getDocument(
          collectionPath: 'users',
          documentId: uid,
          idToken: idToken,
        );
        if (doc != null) applicants.add(doc);
      } catch (_) {}
    }

    return <String, dynamic>{
      'items': takenItems,
      'count': takenItems.length,
      'applicants': applicants,
      if (roomId.isNotEmpty) 'chatRoomId': roomId,
    };
  }

  Future<Map<String, dynamic>> createQuote({
    required String idToken,
    String? role,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);

    final quoteData =
        _mapOrNull(payload['quoteData']) ?? _buildQuoteData(payload);
    if (quoteData.isEmpty) {
      throw ApiException.badRequest('quoteData is required.');
    }
    
    final quoteJobId = '${quoteData['jobId'] ?? ''}'.trim();
    
    String otherId = _optionalString(payload, 'otherId') ?? 
                     _optionalString(payload, 'receiverId') ?? 
                     _optionalString(payload, 'customerId') ?? 
                     _optionalString(payload, 'vendorId') ?? '';
                     
    // If quoting a job and otherId wasn't given, auto-derive it from the job post.                 
    if (otherId.isEmpty && quoteJobId.isNotEmpty) {
      final job = await _firestoreClient.getDocument(
        collectionPath: 'job_posts',
        documentId: quoteJobId,
        idToken: idToken,
      );
      if (job != null) {
        otherId = '${job['customerId'] ?? ''}'.trim();
      }
    }
    
    if (otherId.isEmpty) {
      throw ApiException.badRequest(
        'Could not determine receiver. Please provide otherId or a valid quoteData.jobId',
      );
    }

    final roomId = _optionalString(payload, 'chatRoomId') ??
        _buildChatRoomId(actor.uid, otherId);

    final projectName = '${quoteData['projectName'] ?? ''}'.trim();
    final text = _optionalString(payload, 'text') ??
        (projectName.isEmpty
            ? 'New project quote'
            : 'Quote submitted for: $projectName');

    final messagePayload = <String, dynamic>{
      ...payload,
      'otherId': otherId,
      'text': text,
      'isQuoteRequest': true,
      'quoteStatus': _optionalString(payload, 'quoteStatus') ?? 'pending',
      'quoteData': quoteData,
      'isNegotiatedQuote': _asBool(payload['isNegotiatedQuote']) ?? false,
      'imageUrls': _readStringList(payload['imageUrls']),
      'videoUrls': _readStringList(payload['videoUrls']),
    };

    final sent = await _chatService.sendMessage(
      idToken: idToken,
      chatRoomId: roomId,
      payload: messagePayload,
      role: actor.role,
    );

    if (quoteJobId.isNotEmpty && actor.isVendor) {
      await _appendApplicant(
        idToken: idToken,
        jobId: quoteJobId,
        vendorId: actor.uid,
      );
    }

    return <String, dynamic>{
      'chatRoomId': roomId,
      'quote': sent['message'],
      'chatRoom': sent['chatRoom'],
    };
  }

  Future<Map<String, dynamic>> getQuote({
    required String idToken,
    String? role,
    required String quoteId,
    String? chatRoomId,
    String? otherId,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final roomId = (chatRoomId != null && chatRoomId.trim().isNotEmpty)
        ? chatRoomId.trim()
        : _buildChatRoomId(actor.uid, otherId ?? '');

    if (roomId.isEmpty ||
        !roomId.contains('_') ||
        (roomId.split('_')[0].isEmpty && roomId.split('_')[1].isEmpty)) {
      throw ApiException.badRequest('Valid chatRoomId or artisanId/otherId is required.');
    }
    final message = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: roomId,
      messageId: quoteId.trim(),
      role: role,
    );
    if (message['isQuoteRequest'] != true) {
      throw ApiException.notFound('Quote not found in this chat.');
    }
    return message;
  }

  Future<Map<String, dynamic>> updateQuoteStatus({
    required String idToken,
    String? role,
    required String quoteId,
    String? chatRoomId,
    String? otherId,
    required String status,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final roomId = (chatRoomId != null && chatRoomId.trim().isNotEmpty)
        ? chatRoomId.trim()
        : _buildChatRoomId(actor.uid, otherId ?? '');

    if (roomId.isEmpty ||
        !roomId.contains('_') ||
        (roomId.split('_')[0].isEmpty && roomId.split('_')[1].isEmpty)) {
      throw ApiException.badRequest('Valid chatRoomId or artisanId/otherId is required.');
    }
    final current = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: roomId,
      messageId: quoteId.trim(),
      role: role,
    );
    if (current['isQuoteRequest'] != true) {
      throw ApiException.badRequest('This message is not a quote.');
    }

    final result = await _chatService.updateQuoteStatus(
      idToken: idToken,
      chatRoomId: roomId,
      messageId: quoteId.trim(),
      status: status,
      role: role,
    );
    final updated = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: roomId,
      messageId: quoteId.trim(),
      role: role,
    );

    if (status.toLowerCase() == 'accepted') {
      final quoteData = _mapOrNull(updated['quoteData']) ?? const <String, dynamic>{};
      final jobId = '${quoteData['jobId'] ?? ''}'.trim();
      if (jobId.isNotEmpty) {
        final job = await _firestoreClient.getDocument(
          collectionPath: 'job_posts',
          documentId: jobId,
          idToken: idToken,
        );
        if (job != null) {
          final artisanId = '${updated['senderId'] ?? ''}'.trim();
          await _firestoreClient.setDocument(
            collectionPath: 'job_posts',
            documentId: jobId,
            idToken: idToken,
            data: <String, dynamic>{
              ...job,
              'status': 'progress',
              'assignedVendorId': artisanId,
              'applicants': artisanId.isNotEmpty ? <String>[artisanId] : <String>[],
              'updatedAt': _nowIso(),
            },
          );
        }
      }
    }

    return <String, dynamic>{...result, 'quote': updated};
  }



  Future<void> _appendApplicant({
    required String idToken,
    required String jobId,
    required String vendorId,
  }) async {
    final job = await _firestoreClient.getDocument(
      collectionPath: 'job_posts',
      documentId: jobId,
      idToken: idToken,
    );
    if (job == null) return;
    final applicants = _readStringList(job['applicants']);
    if (!applicants.contains(vendorId)) {
      applicants.add(vendorId);
      await _firestoreClient.setDocument(
        collectionPath: 'job_posts',
        documentId: jobId,
        idToken: idToken,
        data: <String, dynamic>{
          ...job,
          'applicants': applicants,
          'updatedAt': _nowIso(),
        },
      );
    }
  }

  Future<Map<String, dynamic>> _jobOrThrow({
    required String jobId,
    required String idToken,
  }) async {
    final normalized = jobId.trim();
    if (normalized.isEmpty)
      throw ApiException.badRequest('job_id is required.');
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'job_posts',
      documentId: normalized,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Job post not found.');
    return <String, dynamic>{'id': normalized, ...doc};
  }

  Future<List<Map<String, dynamic>>> _quotesForRoom({
    required String idToken,
    required String role,
    required String chatRoomId,
    required int limit,
  }) async {
    final messages = await _chatService.listMessages(
      idToken: idToken,
      chatRoomId: chatRoomId,
      role: role,
      limit: limit,
    );
    final itemsRaw = messages['items'];
    if (itemsRaw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in itemsRaw) {
      final msg = _mapOrNull(item);
      if (msg == null || msg['isQuoteRequest'] != true) continue;
      out.add(<String, dynamic>{...msg, 'chatRoomId': chatRoomId});
    }
    return out;
  }

  Map<String, dynamic> _sanitizeJobUpdates(Map<String, dynamic> payload) {
    final blocked = <String>{
      'id',
      'jobId',
      'customerId',
      'customerName',
      'customerImage',
      'createdAt',
      'timestamp',
    };
    final updates = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (blocked.contains(entry.key)) continue;
      updates[entry.key] = entry.value;
    }

    if (updates.containsKey('refImages')) {
      updates['refImages'] = _readStringList(updates['refImages']);
    }
    if (updates.containsKey('mediaImages')) {
      updates['mediaImages'] = _readStringList(updates['mediaImages']);
    }
    if (updates.containsKey('requirements')) {
      updates['requirements'] = _readStringList(updates['requirements']);
    }
    if (updates.containsKey('applicants')) {
      updates['applicants'] = _readStringList(updates['applicants']);
    }

    final isRemote = _asBool(updates['isRemote']);
    if (updates.containsKey('location') ||
        updates.containsKey('latitude') ||
        updates.containsKey('longitude') ||
        isRemote != null) {
      updates['location'] = _normalizeLocation(
        updates['location'],
        latitude: _asDouble(updates['latitude']),
        longitude: _asDouble(updates['longitude']),
        isRemote: isRemote,
      );
    }
    return updates;
  }

  Map<String, dynamic> _buildQuoteData(Map<String, dynamic> payload) {
    final total = _asDouble(payload['total']) ??
        _asDouble(payload['totalAmount']) ??
        _asDouble(payload['amount']) ??
        0.0;
    final milestones = _normalizeQuoteLineItems(payload['milestones']);
    final materials = _normalizeQuoteLineItems(payload['materials']);
    final laborItems = _normalizeQuoteLineItems(payload['laborItems']);

    final data = <String, dynamic>{
      'projectName': _optionalString(payload, 'projectName') ??
          _optionalString(payload, 'title') ??
          'Job Quote',
      'deliverables': _optionalString(payload, 'deliverables') ??
          _optionalString(payload, 'description') ??
          '',
      'timeframe': _optionalString(payload, 'timeframe') ??
          _optionalString(payload, 'timeline') ??
          'Ready to start',
      'total': total,
      'totalFormatted':
          _optionalString(payload, 'totalFormatted') ?? _formatCurrency(total),
      'hasMilestones':
          _asBool(payload['hasMilestones']) ?? milestones.isNotEmpty,
      'milestones': milestones,
      'materials': materials,
      'laborItems': laborItems,
      'pitch': _optionalString(payload, 'pitch') ?? '',
      'jobId': _optionalString(payload, 'jobId') ?? '',
    };
    if (payload.containsKey('scope')) data['scope'] = payload['scope'];
    return data;
  }

  List<Map<String, dynamic>> _normalizeQuoteLineItems(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      final map = _mapOrNull(item);
      if (map == null) continue;
      out.add(map);
    }
    return out;
  }

  String _formatCurrency(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts.first;
    final decimal = parts.last;
    final formattedWhole = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '\$$formattedWhole.$decimal';
  }

  String _buildChatRoomId(String a, String b) {
    final ids = <String>[a.trim(), b.trim()]..sort();
    return ids.join('_');
  }

  Map<String, dynamic>? _normalizeLocation(
    dynamic raw, {
    required double? latitude,
    required double? longitude,
    required bool? isRemote,
  }) {
    if (isRemote == true) return null;
    if (raw is Map<String, dynamic>) {
      return <String, dynamic>{
        'latitude': _asDouble(raw['latitude']) ?? latitude ?? 0.0,
        'longitude': _asDouble(raw['longitude']) ?? longitude ?? 0.0,
      };
    }
    if (raw is Map) {
      return _normalizeLocation(
        Map<String, dynamic>.from(raw),
        latitude: latitude,
        longitude: longitude,
        isRemote: isRemote,
      );
    }
    if (latitude != null && longitude != null) {
      return <String, dynamic>{'latitude': latitude, 'longitude': longitude};
    }
    return null;
  }

  Future<_ActorContext> _resolveActor({
    required String idToken,
    String? roleHint,
  }) async {
    final uid = await _resolveUid(idToken);
    final hint = roleHint?.trim().toLowerCase();

    if (hint == 'customer') {
      final customer = await _firestoreClient.getDocument(
        collectionPath: 'customers',
        documentId: uid,
        idToken: idToken,
      );
      return _ActorContext(
        uid: uid,
        role: 'customer',
        collection: 'customers',
        profile: customer ?? const <String, dynamic>{},
      );
    }

    if (hint == 'vendor' || hint == 'artisan') {
      final vendor = await _firestoreClient.getDocument(
        collectionPath: 'vendors',
        documentId: uid,
        idToken: idToken,
      );
      if (vendor != null) {
        return _ActorContext(
          uid: uid,
          role: 'vendor',
          collection: 'vendors',
          profile: vendor,
        );
      }
      final artisan = await _firestoreClient.getDocument(
        collectionPath: 'artisans',
        documentId: uid,
        idToken: idToken,
      );
      return _ActorContext(
        uid: uid,
        role: artisan != null ? 'artisan' : (hint ?? 'vendor'),
        collection: artisan != null ? 'artisans' : 'users',
        profile: artisan ?? const <String, dynamic>{},
      );
    }

    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('customers', 'customer'),
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        return _ActorContext(
          uid: uid,
          role: pair.value,
          collection: pair.key,
          profile: doc,
        );
      }
    }

    // Fall back to users collection.
    final usersDoc = await _firestoreClient.getDocument(
      collectionPath: 'users',
      documentId: uid,
      idToken: idToken,
    );
    return _ActorContext(
      uid: uid,
      role: hint ?? 'customer',
      collection: 'users',
      profile: usersDoc ?? const <String, dynamic>{},
    );
  }

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  String _customerName(Map<String, dynamic> profile) {
    return _optionalString(profile, 'username') ??
        _optionalString(profile, 'name') ??
        'Customer';
  }

  String _profileImage(Map<String, dynamic> profile) {
    return _optionalString(profile, 'profileImage') ??
        'https://img.freepik.com/free-vector/user-circles-set_78370-4704.jpg';
  }

  String _jobStatus(Map<String, dynamic> job) {
    return '${job['status'] ?? ''}'.trim().toLowerCase();
  }

  int _timestampMs(dynamic value, {dynamic fallback}) {
    final primary = _singleTimestampMs(value);
    if (primary > 0) return primary;
    return _singleTimestampMs(fallback);
  }

  int _singleTimestampMs(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final asInt = int.tryParse(value.trim());
      if (asInt != null) return asInt;
      final asDate = DateTime.tryParse(value.trim());
      if (asDate != null) return asDate.toUtc().millisecondsSinceEpoch;
    }
    return 0;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _nextId({required String prefix}) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
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

  String _requiredString(
    Map<String, dynamic> payload,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    for (final field in <String>[key, ...aliases]) {
      final value = payload[field];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw ApiException.badRequest(
        '${[key, ...aliases].join('/')} is required.');
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }
}

class _ActorContext {
  const _ActorContext({
    required this.uid,
    required this.role,
    required this.collection,
    required this.profile,
  });

  final String uid;
  final String role;
  final String collection;
  final Map<String, dynamic> profile;

  bool get isCustomer => role == 'customer';

  bool get isVendor => role == 'vendor' || role == 'artisan';
}
