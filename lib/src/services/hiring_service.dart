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
          itemStatus != 'open') {
        // Vendor browse defaults to open jobs to match feed behavior.
        continue;
      }
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
    // Resolve uid directly — don't require a specific collection profile.
    final uid = await _resolveUid(idToken);

    final title = _requiredString(payload, 'title');
    final category = _requiredString(payload, 'category');
    final isRemote = _asBool(payload['isRemote']) ?? false;
    final address = _optionalString(payload, 'address') ?? '';

    // Fetch profile from any collection for customerName/customerImage.
    Map<String, dynamic> profile = const <String, dynamic>{};
    for (final collection in const <String>[
      'customers', 'vendors', 'artisans', 'users',
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: collection,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) { profile = doc; break; }
    }

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
      'status': _optionalString(payload, 'status')?.toLowerCase() ?? 'open',
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
    if ('${existing['customerId'] ?? ''}' != actor.uid) {
      throw ApiException.forbidden('Only the job owner can update this post.');
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

  Future<Map<String, dynamic>> applyToJob({
    required String idToken,
    String? role,
    required String jobId,
    Map<String, dynamic>? payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    if (!actor.isVendor) {
      throw ApiException.forbidden('Only artisans/vendors can apply to jobs.');
    }

    final job = await _jobOrThrow(jobId: jobId, idToken: idToken);
    if ('${job['customerId'] ?? ''}' == actor.uid) {
      throw ApiException.badRequest('You cannot apply to your own job post.');
    }

    final status = _jobStatus(job);
    if (status != 'open') {
      throw ApiException.conflict(
        'This job is no longer accepting applications.',
      );
    }

    final applicants = _readStringList(job['applicants']);
    var applied = false;
    if (!applicants.contains(actor.uid)) {
      applicants.add(actor.uid);
      applied = true;
    }

    final merged = <String, dynamic>{
      ...job,
      'applicants': applicants,
      'updatedAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'job_posts',
      documentId: jobId.trim(),
      idToken: idToken,
      data: merged,
    );

    return <String, dynamic>{
      'jobId': jobId.trim(),
      'applied': applied,
      'applicantCount': applicants.length,
      'applicants': applicants,
      if (payload != null && payload.isNotEmpty) 'meta': payload,
    };
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

    return <String, dynamic>{
      'items': filtered.take(safeLimit).toList(),
      'count': min(filtered.length, safeLimit).toInt(),
      if (roomId.isNotEmpty) 'chatRoomId': roomId,
    };
  }

  Future<Map<String, dynamic>> createQuote({
    required String idToken,
    String? role,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final otherId = _requiredString(
      payload,
      'otherId',
      aliases: const <String>['receiverId', 'customerId', 'vendorId'],
    );
    final roomId = _optionalString(payload, 'chatRoomId') ??
        _buildChatRoomId(actor.uid, otherId);

    final quoteData =
        _mapOrNull(payload['quoteData']) ?? _buildQuoteData(payload);
    if (quoteData.isEmpty) {
      throw ApiException.badRequest('quoteData is required.');
    }

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

    final quoteJobId = '${quoteData['jobId'] ?? ''}'.trim();
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
    required String chatRoomId,
  }) async {
    final message = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: chatRoomId.trim(),
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
    required String chatRoomId,
    required String status,
  }) async {
    final current = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: chatRoomId.trim(),
      messageId: quoteId.trim(),
      role: role,
    );
    if (current['isQuoteRequest'] != true) {
      throw ApiException.badRequest('This message is not a quote.');
    }

    final result = await _chatService.updateQuoteStatus(
      idToken: idToken,
      chatRoomId: chatRoomId.trim(),
      messageId: quoteId.trim(),
      status: status,
      role: role,
    );
    final updated = await _chatService.getMessage(
      idToken: idToken,
      chatRoomId: chatRoomId.trim(),
      messageId: quoteId.trim(),
      role: role,
    );
    return <String, dynamic>{...result, 'quote': updated};
  }

  Future<Map<String, dynamic>> listActiveProjects({
    required String idToken,
    String? role,
    int limit = 30,
    String? pageToken,
    String? status,
    bool? mine,
    String? search,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final safeLimit = limit.clamp(1, 100).toInt();
    final statusFilter = _normalizeProjectStatus(status);
    final searchFilter = search?.trim().toLowerCase();

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'activeProjects',
      idToken: idToken,
      pageSize: max(safeLimit * 4, 80).toInt(),
      orderBy: 'updatedAt desc',
      pageToken: pageToken,
    );

    final mineOnly = mine ?? true;
    final items = <Map<String, dynamic>>[];
    for (final raw in page.documents) {
      final item = <String, dynamic>{...raw, 'id': '${raw['id'] ?? ''}'};
      if (mineOnly && !_isProjectMine(item, actor)) continue;

      final projectStatus = _normalizeProjectStatus(
          '${item['projectStatus'] ?? item['status'] ?? ''}');
      if (statusFilter.isNotEmpty) {
        final acceptedValues = <String>{
          projectStatus,
          if (projectStatus == 'ongoing') 'in_progress',
          if (projectStatus == 'in_progress') 'ongoing',
        };
        if (!acceptedValues.contains(statusFilter)) continue;
      }
      if (searchFilter != null && searchFilter.isNotEmpty) {
        final haystack = <String>[
          '${item['title'] ?? ''}',
          '${item['projectName'] ?? ''}',
          '${item['description'] ?? ''}',
          '${item['assignedVendorName'] ?? ''}',
        ].join(' ').toLowerCase();
        if (!haystack.contains(searchFilter)) continue;
      }
      items.add(item);
    }

    items.sort(
      (a, b) =>
          _timestampMs(b['updatedAt']).compareTo(_timestampMs(a['updatedAt'])),
    );

    return <String, dynamic>{
      'items': items.take(safeLimit).toList(),
      'count': min(items.length, safeLimit).toInt(),
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> getActiveProject({
    required String idToken,
    String? role,
    required String projectId,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final project = await _activeProjectOrThrow(
      projectId: projectId.trim(),
      idToken: idToken,
    );
    if (!_isProjectMine(project, actor)) {
      throw ApiException.forbidden('You do not have access to this project.');
    }
    return project;
  }

  Future<Map<String, dynamic>> updateActiveProject({
    required String idToken,
    String? role,
    required String projectId,
    required Map<String, dynamic> payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final current = await _activeProjectOrThrow(
      projectId: projectId.trim(),
      idToken: idToken,
    );
    if (!_isProjectMine(current, actor)) {
      throw ApiException.forbidden('You do not have access to this project.');
    }

    final status = _normalizeProjectStatus(
      _optionalString(payload, 'status') ??
          _optionalString(payload, 'projectStatus'),
    );
    if (status.isNotEmpty) {
      final voteStatus = status == 'in_progress' ? 'ongoing' : status;
      final voted = await _chatService.voteProjectStatus(
        idToken: idToken,
        chatRoomId: projectId.trim(),
        status: voteStatus,
        role: actor.role,
      );
      final refreshed = await _activeProjectOrThrow(
        projectId: projectId.trim(),
        idToken: idToken,
      );
      return <String, dynamic>{...voted, 'project': refreshed};
    }

    final updates = Map<String, dynamic>.from(payload)
      ..removeWhere((key, _) => const <String>{
            'id',
            'chatRoomId',
            'customerId',
            'vendorId',
            'assignedVendorId',
          }.contains(key));
    if (updates.isEmpty) {
      throw ApiException.badRequest('No editable fields were provided.');
    }
    final merged = <String, dynamic>{
      ...current,
      ...updates,
      'updatedAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: 'activeProjects',
      documentId: projectId.trim(),
      idToken: idToken,
      data: merged,
    );
    return merged;
  }

  Future<Map<String, dynamic>> deleteActiveProject({
    required String idToken,
    String? role,
    required String projectId,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final current = await _activeProjectOrThrow(
      projectId: projectId.trim(),
      idToken: idToken,
    );
    if ('${current['customerId'] ?? ''}' != actor.uid) {
      throw ApiException.forbidden(
          'Only the customer can remove this project.');
    }
    await _firestoreClient.deleteDocument(
      collectionPath: 'activeProjects',
      documentId: projectId.trim(),
      idToken: idToken,
    );
    return <String, dynamic>{'deleted': true, 'projectId': projectId.trim()};
  }

  String _normalizeProjectStatus(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'in_progress') return 'ongoing';
    return normalized;
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

  Future<Map<String, dynamic>> _activeProjectOrThrow({
    required String projectId,
    required String idToken,
  }) async {
    final normalized = projectId.trim();
    if (normalized.isEmpty) {
      throw ApiException.badRequest('project_id is required.');
    }
    final doc = await _firestoreClient.getDocument(
      collectionPath: 'activeProjects',
      documentId: normalized,
      idToken: idToken,
    );
    if (doc == null) throw ApiException.notFound('Active project not found.');
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

  Future<Map<String, dynamic>> _requireProfile({
    required String collectionPath,
    required String userId,
    required String idToken,
  }) async {
    final profile = await _firestoreClient.getDocument(
      collectionPath: collectionPath,
      documentId: userId,
      idToken: idToken,
    );
    if (profile == null) {
      throw ApiException.notFound('Profile not found.');
    }
    return profile;
  }

  bool _isProjectMine(Map<String, dynamic> project, _ActorContext actor) {
    final customerId = '${project['customerId'] ?? ''}'.trim();
    final vendorId = '${project['vendorId'] ?? ''}'.trim();
    final assignedVendorId = '${project['assignedVendorId'] ?? ''}'.trim();
    if (actor.isCustomer) return customerId == actor.uid;
    return vendorId == actor.uid || assignedVendorId == actor.uid;
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
        role: artisan != null ? 'artisan' : hint,
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
