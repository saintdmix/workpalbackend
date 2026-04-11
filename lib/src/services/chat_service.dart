import 'dart:math';

import 'package:workpalbackend/src/config/env.dart';
import 'package:workpalbackend/src/exceptions/api_exception.dart';
import 'package:workpalbackend/src/firebase/firebase_auth_rest_client.dart';
import 'package:workpalbackend/src/firebase/firestore_rest_client.dart';

final chatService = ChatService();

class ChatService {
  ChatService({
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
  final Random _random = Random();

  Future<Map<String, dynamic>> listChatRooms({
    required String idToken,
    String? role,
    int limit = 20,
    String? pageToken,
    String? search,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final pinnedChats = _readStringList(profile['pinnedChats']);

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'chatRooms',
      idToken: idToken,
      pageSize: max(limit.clamp(1, 100).toInt() * 3, 50).toInt(),
      orderBy: 'lastMessageTimestamp desc',
      pageToken: pageToken,
    );

    final items = <Map<String, dynamic>>[];
    for (final doc in page.documents) {
      // Firestore REST list is broad, so we enforce participant membership here.
      if (!_participantsContain(doc, actor.uid)) continue;
      final needle = (search ?? '').trim().toLowerCase();
      if (needle.isNotEmpty) {
        final label = actor.isVendor
            ? '${doc['customerName'] ?? ''}'
            : '${doc['vendorName'] ?? ''}';
        if (!label.toLowerCase().contains(needle)) continue;
      }
      final id = '${doc['id'] ?? ''}';
      items.add(<String, dynamic>{
        ...doc,
        'isPinned': pinnedChats.contains(id),
        'unreadCount': _toInt(doc['unreadCount_${actor.uid}']),
      });
    }

    items.sort((a, b) {
      final aPinned = a['isPinned'] == true;
      final bPinned = b['isPinned'] == true;
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return _timestampMs(b['lastMessageTimestamp'])
          .compareTo(_timestampMs(a['lastMessageTimestamp']));
    });

    var unread = 0;
    for (final item in items) {
      unread += _toInt(item['unreadCount']);
    }

    return <String, dynamic>{
      'items': items.take(limit.clamp(1, 100).toInt()).toList(),
      'unreadCount': unread,
      'pinnedChats': pinnedChats,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> getChatRoom({
    required String idToken,
    required String chatRoomId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);
    return room;
  }

  Future<Map<String, dynamic>> upsertChatRoom({
    required String idToken,
    required String chatRoomId,
    required String otherId,
    String? role,
    Map<String, dynamic>? payload,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final me = await _ensureActorProfile(actor: actor, idToken: idToken);
    final peer = await _resolveOtherProfile(
      actorIsVendor: actor.isVendor,
      otherId: otherId,
      idToken: idToken,
    );
    final existing = await _firestoreClient.getDocument(
          collectionPath: 'chatRooms',
          documentId: chatRoomId.trim(),
          idToken: idToken,
        ) ??
        <String, dynamic>{};

    final merged = <String, dynamic>{
      ...existing,
      'participants': <String>[actor.uid, otherId.trim()],
      'vendorId': actor.isVendor ? actor.uid : otherId.trim(),
      'customerId': actor.isVendor ? otherId.trim() : actor.uid,
      'vendorName':
          actor.isVendor ? _displayName(me, true) : _displayName(peer, true),
      'customerName':
          actor.isVendor ? _displayName(peer, false) : _displayName(me, false),
      'vendorImage': actor.isVendor ? _profileImage(me) : _profileImage(peer),
      'customerImage': actor.isVendor ? _profileImage(peer) : _profileImage(me),
      'updatedAt': _nowIso(),
    };
    if (payload != null) merged.addAll(payload);

    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms',
      documentId: chatRoomId.trim(),
      idToken: idToken,
      data: merged,
    );

    return <String, dynamic>{'id': chatRoomId.trim(), ...merged};
  }

  Future<Map<String, dynamic>> listMessages({
    required String idToken,
    required String chatRoomId,
    String? role,
    int limit = 50,
    String? pageToken,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);

    final page = await _firestoreClient.listDocumentsPage(
      collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
      idToken: idToken,
      pageSize: limit.clamp(1, 200).toInt(),
      orderBy: 'timestamp asc',
      pageToken: pageToken,
    );

    final items = <Map<String, dynamic>>[];
    for (final doc in page.documents) {
      if (_readStringList(doc['deletedFor']).contains(actor.uid)) continue;
      items.add(<String, dynamic>{
        ...doc,
        'id': '${doc['id'] ?? doc['messageId'] ?? ''}',
      });
    }

    return <String, dynamic>{
      'items': items,
      if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
    };
  }

  Future<Map<String, dynamic>> getMessage({
    required String idToken,
    required String chatRoomId,
    required String messageId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);
    final message = await _getMessageOrThrow(
      chatRoomId: chatRoomId,
      messageId: messageId,
      idToken: idToken,
    );
    if (_readStringList(message['deletedFor']).contains(actor.uid)) {
      throw ApiException.notFound('Message not found.');
    }
    return message;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String idToken,
    required String chatRoomId,
    required Map<String, dynamic> payload,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final me = await _ensureActorProfile(actor: actor, idToken: idToken);
    final otherId =
        _requiredString(payload, 'otherId', aliases: <String>['receiverId']);

    await _assertCanMessage(
      actor: actor,
      actorProfile: me,
      otherId: otherId,
      idToken: idToken,
    );

    final text = _optionalString(payload, 'text');
    final audioUrl = _optionalString(payload, 'audioUrl');
    final imageUrls = _readStringList(payload['imageUrls']);
    final videoUrls = _readStringList(payload['videoUrls']);
    final isQuote = payload['isQuoteRequest'] == true;
    if ((text == null || text.isEmpty) &&
        audioUrl == null &&
        imageUrls.isEmpty &&
        videoUrls.isEmpty &&
        !isQuote) {
      throw ApiException.badRequest('Message body is empty.');
    }

    final roomId = chatRoomId.trim();
    final room = await _firestoreClient.getDocument(
          collectionPath: 'chatRooms',
          documentId: roomId,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    if (room.isNotEmpty)
      _ensureParticipantOrPeer(room: room, uid: actor.uid, otherId: otherId);

    final messageId =
        _optionalString(payload, 'messageId') ?? _nextId(prefix: 'm');
    final timestamp = _nowIso();
    final message = <String, dynamic>{
      'messageId': messageId,
      'senderId': actor.uid,
      'receiverId': otherId,
      'text': text,
      'audioUrl': audioUrl,
      'audioDuration': _optionalInt(payload, 'audioDuration'),
      'imageUrls': imageUrls.isEmpty ? null : imageUrls,
      'videoUrls': videoUrls.isEmpty ? null : videoUrls,
      'timestamp': timestamp,
      'isRead': false,
      'isDeleted': false,
      'deletedFor': <dynamic>[],
      'replyToId': _optionalString(payload, 'replyToId'),
      'replyToText': _optionalString(payload, 'replyToText'),
      'replyToSenderId': _optionalString(payload, 'replyToSenderId'),
      'audioPlayed': payload['audioPlayed'] == true,
      'isQuoteRequest': isQuote,
      'quoteData': _mapOrNull(payload['quoteData']),
      'quoteStatus': _optionalString(payload, 'quoteStatus') ?? 'pending',
      'isForwarded': payload['isForwarded'] == true,
      'originalSenderId': _optionalString(payload, 'originalSenderId'),
      'isNegotiatedQuote': payload['isNegotiatedQuote'] == true,
    };

    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms/$roomId/messages',
      documentId: messageId,
      idToken: idToken,
      data: message,
    );

    final peer = await _resolveOtherProfile(
      actorIsVendor: actor.isVendor,
      otherId: otherId,
      idToken: idToken,
    );
    final mergedRoom = _mergeRoomAfterMessage(
      room: room,
      actor: actor,
      me: me,
      peer: peer,
      otherId: otherId,
      timestamp: timestamp,
      preview: _messagePreview(message),
    );
    // Keep chat-room summary fields in sync for chat-list rendering.
    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms',
      documentId: roomId,
      idToken: idToken,
      data: mergedRoom,
    );

    return <String, dynamic>{
      'chatRoomId': roomId,
      'message': <String, dynamic>{'id': messageId, ...message},
      'chatRoom': <String, dynamic>{'id': roomId, ...mergedRoom},
    };
  }

  Future<Map<String, dynamic>> markMessagesAsRead({
    required String idToken,
    required String chatRoomId,
    required String otherId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);

    final messages = await _firestoreClient.listDocuments(
      collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
      idToken: idToken,
      pageSize: 400,
      orderBy: 'timestamp asc',
    );

    var updated = 0;
    for (final msg in messages) {
      if ('${msg['senderId'] ?? ''}' != otherId.trim()) continue;
      if (msg['isRead'] == true) continue;
      final id = '${msg['id'] ?? ''}';
      if (id.isEmpty) continue;
      await _firestoreClient.setDocument(
        collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
        documentId: id,
        idToken: idToken,
        data: <String, dynamic>{...msg, 'isRead': true},
      );
      updated++;
    }

    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms',
      documentId: chatRoomId.trim(),
      idToken: idToken,
      data: <String, dynamic>{
        ...room,
        'unreadCount_${actor.uid}': 0,
        'updatedAt': _nowIso(),
      },
    );

    return <String, dynamic>{
      'chatRoomId': chatRoomId.trim(),
      'updatedMessages': updated,
      'unreadCount': 0,
    };
  }

  Future<Map<String, dynamic>> applyMessageAction({
    required String idToken,
    required String chatRoomId,
    required String messageId,
    required String action,
    required Map<String, dynamic> payload,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);
    final msg = await _getMessageOrThrow(
      chatRoomId: chatRoomId,
      messageId: messageId,
      idToken: idToken,
    );

    final normalized = action.trim().toLowerCase();
    if (normalized == 'add_reaction') {
      final emoji = _requiredString(payload, 'emoji');
      final reactions = _mapOrEmpty(msg['reactions']);
      reactions[actor.uid] = emoji;
      final updated = <String, dynamic>{...msg, 'reactions': reactions};
      await _saveMessage(
          chatRoomId: chatRoomId,
          messageId: messageId,
          idToken: idToken,
          data: updated);
      return <String, dynamic>{
        'messageId': messageId.trim(),
        'reactions': reactions
      };
    }

    if (normalized == 'mark_audio_played') {
      final updated = <String, dynamic>{...msg, 'audioPlayed': true};
      await _saveMessage(
          chatRoomId: chatRoomId,
          messageId: messageId,
          idToken: idToken,
          data: updated);
      return <String, dynamic>{
        'messageId': messageId.trim(),
        'audioPlayed': true
      };
    }

    if (normalized == 'delete_for_me') {
      final deletedFor = _readStringList(msg['deletedFor']);
      if (!deletedFor.contains(actor.uid)) deletedFor.add(actor.uid);
      final updated = <String, dynamic>{...msg, 'deletedFor': deletedFor};
      await _saveMessage(
          chatRoomId: chatRoomId,
          messageId: messageId,
          idToken: idToken,
          data: updated);
      return <String, dynamic>{
        'messageId': messageId.trim(),
        'deletedFor': deletedFor
      };
    }

    if (normalized == 'delete_for_everyone') {
      if ('${msg['senderId'] ?? ''}' != actor.uid) {
        throw ApiException.forbidden('Only sender can delete for everyone.');
      }
      final updated = <String, dynamic>{
        ...msg,
        'text': 'This message was deleted',
        'audioUrl': null,
        'imageUrls': null,
        'videoUrls': null,
        'isDeleted': true,
        'updatedAt': _nowIso(),
      };
      await _saveMessage(
          chatRoomId: chatRoomId,
          messageId: messageId,
          idToken: idToken,
          data: updated);
      return <String, dynamic>{
        'messageId': messageId.trim(),
        'deletedForEveryone': true
      };
    }

    throw ApiException.badRequest(
      'action must be one of: add_reaction, mark_audio_played, delete_for_me, delete_for_everyone.',
    );
  }

  Future<Map<String, dynamic>> forwardMessage({
    required String idToken,
    required Map<String, dynamic> payload,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final source = _mapOrNull(payload['sourceMessage']) ??
        await _getMessageOrThrow(
          chatRoomId: _requiredString(payload, 'sourceChatRoomId'),
          messageId: _requiredString(payload, 'sourceMessageId'),
          idToken: idToken,
        );
    final targetRoomIds = _readStringList(payload['targetChatRoomIds']);
    if (targetRoomIds.isEmpty) {
      throw ApiException.badRequest('targetChatRoomIds is required.');
    }

    var forwardedCount = 0;
    final failedRooms = <String>[];
    for (final roomId in targetRoomIds) {
      try {
        final room =
            await _getRoomOrThrow(chatRoomId: roomId, idToken: idToken);
        _ensureParticipant(room: room, uid: actor.uid);
        final peers = _readStringList(room['participants']);
        final receiverId =
            peers.firstWhere((id) => id != actor.uid, orElse: () => '');
        if (receiverId.isEmpty) {
          throw ApiException.badRequest('Receiver not found for room $roomId.');
        }

        final messageId = _nextId(prefix: 'm');
        final timestamp = _nowIso();
        final forwarded = <String, dynamic>{
          'messageId': messageId,
          'senderId': actor.uid,
          'receiverId': receiverId,
          'text': source['text'],
          'audioUrl': source['audioUrl'],
          'audioDuration': source['audioDuration'],
          'imageUrls': source['imageUrls'],
          'videoUrls': source['videoUrls'],
          'timestamp': timestamp,
          'isRead': false,
          'isForwarded': true,
          'originalSenderId': '${source['senderId'] ?? ''}',
          'isDeleted': false,
          'deletedFor': <dynamic>[],
        };

        await _saveMessage(
          chatRoomId: roomId,
          messageId: messageId,
          idToken: idToken,
          data: forwarded,
        );
        await _firestoreClient.setDocument(
          collectionPath: 'chatRooms',
          documentId: roomId,
          idToken: idToken,
          data: <String, dynamic>{
            ...room,
            'lastMessage': 'Forwarded: ${_messagePreview(forwarded)}',
            'lastMessageTimestamp': timestamp,
            'unreadCount_$receiverId':
                _toInt(room['unreadCount_$receiverId']) + 1,
            'updatedAt': timestamp,
          },
        );
        forwardedCount++;
      } catch (_) {
        failedRooms.add(roomId);
      }
    }

    return <String, dynamic>{
      'forwardedCount': forwardedCount,
      'targetCount': targetRoomIds.length,
      if (failedRooms.isNotEmpty) 'failedRooms': failedRooms,
    };
  }

  Future<Map<String, dynamic>> updateQuoteStatus({
    required String idToken,
    required String chatRoomId,
    required String messageId,
    required String status,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);
    final msg = await _getMessageOrThrow(
      chatRoomId: chatRoomId,
      messageId: messageId,
      idToken: idToken,
    );

    final normalized = status.trim().toLowerCase();
    if (!<String>{'pending', 'accepted', 'declined', 'negotiating'}
        .contains(normalized)) {
      throw ApiException.badRequest(
        'status must be pending, accepted, declined, or negotiating.',
      );
    }

    await _saveMessage(
      chatRoomId: chatRoomId,
      messageId: messageId,
      idToken: idToken,
      data: <String, dynamic>{
        ...msg,
        'quoteStatus': normalized,
        'updatedAt': _nowIso()
      },
    );

    if (normalized == 'accepted') {
      final updatedRoom = <String, dynamic>{
        ...room,
        'projectStatus': 'accepted',
        'vendorStatusVote': 'accepted',
        'customerStatusVote': 'accepted',
        'updatedAt': _nowIso(),
      };
      await _firestoreClient.setDocument(
        collectionPath: 'chatRooms',
        documentId: chatRoomId.trim(),
        idToken: idToken,
        data: updatedRoom,
      );
      await _syncActiveProject(
        idToken: idToken,
        chatRoomId: chatRoomId.trim(),
        room: updatedRoom,
        quoteMessage: msg,
        status: 'accepted',
      );
      await _syncJobPostStatus(
        idToken: idToken,
        quoteMessage: msg,
        status: 'accepted',
        vendorId: '${updatedRoom['vendorId'] ?? ''}',
      );
    }

    return <String, dynamic>{
      'chatRoomId': chatRoomId.trim(),
      'messageId': messageId.trim(),
      'quoteStatus': normalized,
    };
  }

  Future<Map<String, dynamic>> voteProjectStatus({
    required String idToken,
    required String chatRoomId,
    required String status,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);

    final normalized = status.trim().toLowerCase();
    if (!<String>{'accepted', 'ongoing', 'completed'}.contains(normalized)) {
      throw ApiException.badRequest(
          'status must be accepted, ongoing, or completed.');
    }

    final actorIsVendor = '${room['vendorId'] ?? ''}' == actor.uid
        ? true
        : '${room['customerId'] ?? ''}' == actor.uid
            ? false
            : actor.isVendor;
    final myVoteKey = actorIsVendor ? 'vendorStatusVote' : 'customerStatusVote';
    final otherVoteKey =
        actorIsVendor ? 'customerStatusVote' : 'vendorStatusVote';
    final otherVote = '${room[otherVoteKey] ?? 'none'}'.trim().toLowerCase();

    final updated = <String, dynamic>{
      ...room,
      myVoteKey: normalized,
      'updatedAt': _nowIso()
    };
    var officialStatus = '${room['projectStatus'] ?? 'none'}';
    // Match your app rule: customer can force-complete, otherwise both votes must match.
    if (!actorIsVendor && normalized == 'completed') {
      officialStatus = 'completed';
      updated['projectStatus'] = officialStatus;
    } else if (otherVote == normalized) {
      officialStatus = normalized;
      updated['projectStatus'] = officialStatus;
    }

    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms',
      documentId: chatRoomId.trim(),
      idToken: idToken,
      data: updated,
    );

    if (officialStatus == normalized) {
      final latestQuote = await _findLatestQuoteMessage(
        idToken: idToken,
        chatRoomId: chatRoomId.trim(),
      );
      await _syncActiveProject(
        idToken: idToken,
        chatRoomId: chatRoomId.trim(),
        room: updated,
        quoteMessage: latestQuote,
        status: officialStatus,
      );
      await _syncJobPostStatus(
        idToken: idToken,
        quoteMessage: latestQuote,
        status: officialStatus,
        vendorId: '${updated['vendorId'] ?? ''}',
      );
    }

    return <String, dynamic>{
      'chatRoomId': chatRoomId.trim(),
      'projectStatus': officialStatus,
      'vendorStatusVote': '${updated['vendorStatusVote'] ?? 'none'}',
      'customerStatusVote': '${updated['customerStatusVote'] ?? 'none'}',
    };
  }

  Future<Map<String, dynamic>> getUnreadSummary({
    required String idToken,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final rooms = await _listAllRoomsForUser(
      idToken: idToken,
      uid: actor.uid,
      maxPages: 12,
    );
    var count = 0;
    for (final room in rooms) {
      count += _toInt(room['unreadCount_${actor.uid}']);
    }
    return <String, dynamic>{'unreadCount': count};
  }

  Future<Map<String, dynamic>> setPinnedChat({
    required String idToken,
    required String chatRoomId,
    required bool pinned,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final pinnedChats = _readStringList(profile['pinnedChats']);
    final roomId = chatRoomId.trim();
    if (roomId.isEmpty)
      throw ApiException.badRequest('chatRoomId is required.');

    if (pinned) {
      if (!pinnedChats.contains(roomId)) pinnedChats.add(roomId);
    } else {
      pinnedChats.removeWhere((id) => id == roomId);
    }

    await _firestoreClient.setDocument(
      collectionPath: actor.collection,
      documentId: actor.uid,
      idToken: idToken,
      data: <String, dynamic>{
        ...profile,
        'pinnedChats': pinnedChats,
        'updatedAt': _nowIso()
      },
    );
    return <String, dynamic>{
      'chatRoomId': roomId,
      'pinned': pinned,
      'pinnedChats': pinnedChats
    };
  }

  Future<Map<String, dynamic>> getPinnedChats({
    required String idToken,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    return <String, dynamic>{
      'pinnedChats': _readStringList(profile['pinnedChats'])
    };
  }

  Future<Map<String, dynamic>> setBlockedUser({
    required String idToken,
    required String otherId,
    required bool blocked,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final blockedUsers = _readStringList(profile['blockedUsers']);
    final target = otherId.trim();
    if (target.isEmpty) throw ApiException.badRequest('otherId is required.');

    if (blocked) {
      if (!blockedUsers.contains(target)) blockedUsers.add(target);
    } else {
      blockedUsers.removeWhere((id) => id == target);
    }

    await _firestoreClient.setDocument(
      collectionPath: actor.collection,
      documentId: actor.uid,
      idToken: idToken,
      data: <String, dynamic>{
        ...profile,
        'blockedUsers': blockedUsers,
        'updatedAt': _nowIso()
      },
    );
    return <String, dynamic>{
      'otherId': target,
      'isBlocked': blocked,
      'blockedUsers': blockedUsers
    };
  }

  Future<Map<String, dynamic>> getBlockedStatus({
    required String idToken,
    required String otherId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final blockedUsers = _readStringList(profile['blockedUsers']);
    final target = otherId.trim();
    return <String, dynamic>{
      'otherId': target,
      'isBlocked': blockedUsers.contains(target),
      'blockedUsers': blockedUsers,
    };
  }

  Future<Map<String, dynamic>> reportUser({
    required String idToken,
    required String otherId,
    required Map<String, dynamic> payload,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final reason = _requiredString(payload, 'reason');
    final now = _nowIso();
    final report = <String, dynamic>{
      'reason': reason,
      'name': _optionalString(payload, 'name') ??
          _optionalString(payload, 'otherName') ??
          'Unknown user',
      'reporterName': _optionalString(payload, 'reporterName') ??
          _displayName(profile, actor.isVendor),
      'reporterId': actor.uid,
      'reportedUserId': otherId.trim(),
      'date': now,
      'status': 'pending',
      'additionalDetails': _optionalString(payload, 'additionalDetails') ?? '',
    };
    await _firestoreClient.setDocument(
      collectionPath: 'reports',
      documentId: otherId.trim(),
      idToken: idToken,
      data: report,
    );
    final history = await _firestoreClient.createDocument(
      collectionPath: 'chat_reports',
      idToken: idToken,
      data: report,
    );
    return <String, dynamic>{
      'report': <String, dynamic>{'id': otherId.trim(), ...report},
      'history': history,
    };
  }

  Future<Map<String, dynamic>> setPresence({
    required String idToken,
    required bool isOnline,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final profile = await _ensureActorProfile(actor: actor, idToken: idToken);
    final now = _nowIso();
    await _firestoreClient.setDocument(
      collectionPath: actor.collection,
      documentId: actor.uid,
      idToken: idToken,
      data: <String, dynamic>{
        ...profile,
        'isOnline': isOnline,
        'lastSeen': now
      },
    );
    return <String, dynamic>{
      'uid': actor.uid,
      'role': actor.role,
      'isOnline': isOnline,
      'lastSeen': now,
    };
  }

  Future<Map<String, dynamic>> getPresence({
    required String idToken,
    required String userId,
  }) async {
    await _resolveUid(idToken);
    final uid = userId.trim();
    if (uid.isEmpty) throw ApiException.badRequest('userId is required.');
    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
      MapEntry<String, String>('customers', 'customer'),
    ]) {
      final doc = await _firestoreClient.getDocument(
        collectionPath: pair.key,
        documentId: uid,
        idToken: idToken,
      );
      if (doc != null) {
        return <String, dynamic>{
          'uid': uid,
          'role': pair.value,
          'isOnline': doc['isOnline'] == true,
          'lastSeen': '${doc['lastSeen'] ?? ''}',
        };
      }
    }
    throw ApiException.notFound('User not found.');
  }

  Future<void> deleteChatRoom({
    required String idToken,
    required String chatRoomId,
    String? role,
  }) async {
    final actor = await _resolveActor(idToken: idToken, roleHint: role);
    final room =
        await _getRoomOrThrow(chatRoomId: chatRoomId, idToken: idToken);
    _ensureParticipant(room: room, uid: actor.uid);
    final messages = await _firestoreClient.listDocuments(
      collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
      idToken: idToken,
      pageSize: 500,
      orderBy: 'timestamp desc',
    );
    for (final msg in messages) {
      final id = '${msg['id'] ?? ''}';
      if (id.isEmpty) continue;
      await _firestoreClient.deleteDocument(
        collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
        documentId: id,
        idToken: idToken,
      );
    }
    await _firestoreClient.deleteDocument(
      collectionPath: 'chatRooms',
      documentId: chatRoomId.trim(),
      idToken: idToken,
    );
  }

  Future<void> _saveMessage({
    required String chatRoomId,
    required String messageId,
    required String idToken,
    required Map<String, dynamic> data,
  }) async {
    await _firestoreClient.setDocument(
      collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
      documentId: messageId.trim(),
      idToken: idToken,
      data: data,
    );
  }

  Future<Map<String, dynamic>> _getRoomOrThrow({
    required String chatRoomId,
    required String idToken,
  }) async {
    final id = chatRoomId.trim();
    if (id.isEmpty) throw ApiException.badRequest('chatRoomId is required.');
    final room = await _firestoreClient.getDocument(
      collectionPath: 'chatRooms',
      documentId: id,
      idToken: idToken,
    );
    if (room == null) throw ApiException.notFound('Chat room not found.');
    return <String, dynamic>{'id': id, ...room};
  }

  Future<Map<String, dynamic>> _getMessageOrThrow({
    required String chatRoomId,
    required String messageId,
    required String idToken,
  }) async {
    final id = messageId.trim();
    if (id.isEmpty) throw ApiException.badRequest('messageId is required.');
    final message = await _firestoreClient.getDocument(
      collectionPath: 'chatRooms/${chatRoomId.trim()}/messages',
      documentId: id,
      idToken: idToken,
    );
    if (message == null) throw ApiException.notFound('Message not found.');
    return <String, dynamic>{'id': id, ...message};
  }

  Future<_ActorContext> _resolveActor({
    required String idToken,
    String? roleHint,
  }) async {
    final uid = await _resolveUid(idToken);
    final hint = roleHint?.trim().toLowerCase();
    if (hint == 'customer') {
      final c = await _firestoreClient.getDocument(
        collectionPath: 'customers',
        documentId: uid,
        idToken: idToken,
      );
      return _ActorContext(
        uid: uid,
        role: 'customer',
        collection: 'customers',
        profile: c ?? const <String, dynamic>{},
      );
    }
    for (final pair in const <MapEntry<String, String>>[
      MapEntry<String, String>('vendors', 'vendor'),
      MapEntry<String, String>('artisans', 'artisan'),
      MapEntry<String, String>('customers', 'customer'),
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
    throw ApiException.unauthorized('User profile not found.');
  }

  Future<Map<String, dynamic>> _ensureActorProfile({
    required _ActorContext actor,
    required String idToken,
  }) async {
    if (actor.profile.isNotEmpty) return actor.profile;
    final profile = <String, dynamic>{
      'uid': actor.uid,
      'blockedUsers': <dynamic>[],
      'pinnedChats': <dynamic>[],
      'isOnline': false,
      'lastSeen': _nowIso(),
      'updatedAt': _nowIso(),
    };
    await _firestoreClient.setDocument(
      collectionPath: actor.collection,
      documentId: actor.uid,
      idToken: idToken,
      data: profile,
    );
    return profile;
  }

  Future<Map<String, dynamic>> _resolveOtherProfile({
    required bool actorIsVendor,
    required String otherId,
    required String idToken,
  }) async {
    final id = otherId.trim();
    if (id.isEmpty) throw ApiException.badRequest('otherId is required.');
    if (actorIsVendor) {
      final customer = await _firestoreClient.getDocument(
        collectionPath: 'customers',
        documentId: id,
        idToken: idToken,
      );
      if (customer == null) throw ApiException.notFound('Customer not found.');
      return customer;
    }
    final vendor = await _firestoreClient.getDocument(
      collectionPath: 'vendors',
      documentId: id,
      idToken: idToken,
    );
    if (vendor != null) return vendor;
    final artisan = await _firestoreClient.getDocument(
      collectionPath: 'artisans',
      documentId: id,
      idToken: idToken,
    );
    if (artisan != null) return artisan;
    throw ApiException.notFound('Vendor not found.');
  }

  Future<void> _assertCanMessage({
    required _ActorContext actor,
    required Map<String, dynamic> actorProfile,
    required String otherId,
    required String idToken,
  }) async {
    final blocked = _readStringList(actorProfile['blockedUsers']);
    if (blocked.contains(otherId)) {
      throw ApiException.forbidden(
          'Unblock this user before sending a message.');
    }
    final otherProfile = await _resolveOtherProfile(
      actorIsVendor: actor.isVendor,
      otherId: otherId,
      idToken: idToken,
    );
    final blockedByOther = _readStringList(otherProfile['blockedUsers']);
    if (blockedByOther.contains(actor.uid)) {
      throw ApiException.forbidden('You cannot message this user right now.');
    }
  }

  Map<String, dynamic> _mergeRoomAfterMessage({
    required Map<String, dynamic> room,
    required _ActorContext actor,
    required Map<String, dynamic> me,
    required Map<String, dynamic> peer,
    required String otherId,
    required String timestamp,
    required String preview,
  }) {
    final merged = <String, dynamic>{
      ...room,
      'participants': <String>[actor.uid, otherId],
      'lastMessage': preview,
      'lastMessageTimestamp': timestamp,
      'updatedAt': timestamp,
      'projectStatus': room['projectStatus'] ?? 'none',
      'vendorStatusVote': room['vendorStatusVote'] ?? 'none',
      'customerStatusVote': room['customerStatusVote'] ?? 'none',
    };
    merged['unreadCount_$otherId'] = _toInt(room['unreadCount_$otherId']) + 1;
    merged['unreadCount_${actor.uid}'] =
        _toInt(room['unreadCount_${actor.uid}']);
    if (actor.isVendor) {
      merged['vendorId'] = actor.uid;
      merged['customerId'] = otherId;
      merged['vendorName'] = _displayName(me, true);
      merged['customerName'] = _displayName(peer, false);
      merged['vendorImage'] = _profileImage(me);
      merged['customerImage'] = _profileImage(peer);
    } else {
      merged['vendorId'] = otherId;
      merged['customerId'] = actor.uid;
      merged['vendorName'] = _displayName(peer, true);
      merged['customerName'] = _displayName(me, false);
      merged['vendorImage'] = _profileImage(peer);
      merged['customerImage'] = _profileImage(me);
    }
    return merged;
  }

  Future<Map<String, dynamic>?> _findLatestQuoteMessage({
    required String idToken,
    required String chatRoomId,
  }) async {
    final messages = await _firestoreClient.listDocuments(
      collectionPath: 'chatRooms/$chatRoomId/messages',
      idToken: idToken,
      pageSize: 300,
      orderBy: 'timestamp desc',
    );
    for (final msg in messages) {
      if (msg['isQuoteRequest'] == true) return msg;
    }
    return null;
  }

  Future<void> _syncActiveProject({
    required String idToken,
    required String chatRoomId,
    required Map<String, dynamic> room,
    required Map<String, dynamic>? quoteMessage,
    required String status,
  }) async {
    final qd = _mapOrNull(quoteMessage?['quoteData']) ?? <String, dynamic>{};
    final payload = <String, dynamic>{
      'chatRoomId': chatRoomId,
      'jobId': qd['jobId'] ?? '',
      'customerId': room['customerId'] ?? '',
      'vendorId': room['vendorId'] ?? '',
      'title': qd['projectName'] ?? room['lastMessage'] ?? 'Project',
      'projectName': qd['projectName'] ?? room['lastMessage'] ?? 'Project',
      'description': qd['deliverables'] ?? '',
      'projectStatus': status,
      'status': _jobStatus(status),
      'progress': _progress(status),
      'assignedVendorId': room['vendorId'] ?? '',
      'assignedVendorName': room['vendorName'] ?? '',
      'assignedVendorImage': room['vendorImage'] ?? '',
      'customerStatusVote': room['customerStatusVote'] ?? 'none',
      'vendorStatusVote': room['vendorStatusVote'] ?? 'none',
      'updatedAt': _nowIso(),
      if (status == 'accepted') 'acceptedAt': _nowIso(),
    };
    final existing = await _firestoreClient.getDocument(
          collectionPath: 'activeProjects',
          documentId: chatRoomId,
          idToken: idToken,
        ) ??
        <String, dynamic>{};
    await _firestoreClient.setDocument(
      collectionPath: 'activeProjects',
      documentId: chatRoomId,
      idToken: idToken,
      data: <String, dynamic>{...existing, ...payload},
    );
  }

  Future<void> _syncJobPostStatus({
    required String idToken,
    required Map<String, dynamic>? quoteMessage,
    required String status,
    required String vendorId,
  }) async {
    final qd = _mapOrNull(quoteMessage?['quoteData']);
    final jobId = '${qd?['jobId'] ?? ''}'.trim();
    if (jobId.isEmpty) return;
    final job = await _firestoreClient.getDocument(
      collectionPath: 'job_posts',
      documentId: jobId,
      idToken: idToken,
    );
    if (job == null) return;
    await _firestoreClient.setDocument(
      collectionPath: 'job_posts',
      documentId: jobId,
      idToken: idToken,
      data: <String, dynamic>{
        ...job,
        'status': _jobStatus(status),
        if (vendorId.trim().isNotEmpty) 'assignedVendorId': vendorId.trim(),
        'updatedAt': _nowIso(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> _listAllRoomsForUser({
    required String idToken,
    required String uid,
    int maxPages = 10,
  }) async {
    final out = <Map<String, dynamic>>[];
    String? token;
    var loops = 0;
    while (loops < maxPages) {
      final page = await _firestoreClient.listDocumentsPage(
        collectionPath: 'chatRooms',
        idToken: idToken,
        pageSize: 100,
        orderBy: 'lastMessageTimestamp desc',
        pageToken: token,
      );
      for (final room in page.documents) {
        if (_participantsContain(room, uid)) out.add(room);
      }
      loops++;
      token = page.nextPageToken;
      if (token == null || page.documents.isEmpty) break;
    }
    return out;
  }

  bool _participantsContain(Map<String, dynamic> room, String uid) {
    return _readStringList(room['participants']).contains(uid);
  }

  void _ensureParticipant({
    required Map<String, dynamic> room,
    required String uid,
  }) {
    if (!_participantsContain(room, uid)) {
      throw ApiException.forbidden(
          'You are not a participant in this chat room.');
    }
  }

  void _ensureParticipantOrPeer({
    required Map<String, dynamic> room,
    required String uid,
    required String otherId,
  }) {
    final participants = _readStringList(room['participants']);
    if (participants.isEmpty) return;
    if (!(participants.contains(uid) && participants.contains(otherId))) {
      throw ApiException.forbidden(
          'chatRoomId does not match the provided participants.');
    }
  }

  String _displayName(Map<String, dynamic> profile, bool isVendor) {
    final value = isVendor
        ? _optionalString(profile, 'name')
        : _optionalString(profile, 'username') ??
            _optionalString(profile, 'name');
    return value ?? (isVendor ? 'Vendor' : 'Customer');
  }

  String _profileImage(Map<String, dynamic> profile) {
    return _optionalString(profile, 'profileImage') ??
        'https://img.freepik.com/free-vector/user-circles-set_78370-4704.jpg';
  }

  String _messagePreview(Map<String, dynamic> message) {
    final text = _optionalString(message, 'text');
    if (text != null && text.isNotEmpty) return text;
    if (_optionalString(message, 'audioUrl') != null) return 'Audio message';
    if (_readStringList(message['imageUrls']).isNotEmpty) return 'Image';
    if (_readStringList(message['videoUrls']).isNotEmpty) return 'Video';
    if (message['isQuoteRequest'] == true) return 'Quote request';
    return 'Message';
  }

  int _timestampMs(dynamic value) {
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

  int _progress(String status) {
    switch (status.trim().toLowerCase()) {
      case 'accepted':
        return 25;
      case 'ongoing':
      case 'in_progress':
        return 65;
      case 'completed':
        return 100;
      default:
        return 0;
    }
  }

  String _jobStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'ongoing' ? 'in_progress' : s;
  }

  String _nextId({required String prefix}) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${micros}_$suffix';
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Future<String> _resolveUid(String idToken) async {
    final user = await _authClient.lookup(idToken: idToken);
    final uid = '${user['localId'] ?? ''}'.trim();
    if (uid.isEmpty) {
      throw ApiException.unauthorized('Invalid or expired user token.');
    }
    return uid;
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic> _mapOrEmpty(dynamic value) {
    return _mapOrNull(value) ?? <String, dynamic>{};
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return <String>[];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) out.add(item.trim());
    }
    return out;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  String _requiredString(
    Map<String, dynamic> payload,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final keys = <String>[key, ...aliases];
    for (final k in keys) {
      final value = payload[k];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw ApiException.badRequest('${keys.join('/')} is required.');
  }

  String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  int? _optionalInt(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
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

  bool get isVendor => role == 'vendor' || role == 'artisan';
}
