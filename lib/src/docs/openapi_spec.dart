Map<String, dynamic> buildOpenApiSpec({
  required Uri requestUri,
}) {
  final origin = requestUri.origin.isEmpty
      ? 'http://localhost:8080'
      : requestUri.origin;

  return <String, dynamic>{
    'openapi': '3.0.3',
    'info': <String, dynamic>{
      'title': 'Workpal Backend API',
      'version': '1.0.0',
      'description':
          'HTTP APIs for auth, profile, stories, notifications, and workfeeds.',
    },
    'servers': <Map<String, dynamic>>[
      <String, dynamic>{'url': origin},
    ],
    'components': <String, dynamic>{
      'securitySchemes': <String, dynamic>{
        'bearerAuth': <String, dynamic>{
          'type': 'http',
          'scheme': 'bearer',
          'bearerFormat': 'JWT',
        },
      },
      'schemas': <String, dynamic>{
        'Error': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'error': <String, dynamic>{'type': 'string'},
          },
        },
      },
    },
    'paths': <String, dynamic>{
      '/auth/customer/sign_up': <String, dynamic>{
        'post': _operation(
          summary: 'Sign up customer',
          tag: 'Auth',
          requestBodyDescription: 'Customer registration payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'email': _stringSchema(description: 'Customer email'),
              'password': _stringSchema(description: 'Customer password'),
              'username': _stringSchema(description: 'Display username'),
              'phone': _stringSchema(description: 'Phone number'),
              'address': _stringSchema(description: 'Address'),
              'lat': <String, dynamic>{'type': 'number'},
              'lng': <String, dynamic>{'type': 'number'},
              'referralCode': _stringSchema(
                description: 'Optional referral code',
              ),
            },
            required: const <String>['email', 'password', 'username'],
          ),
          requestBodyExample: <String, dynamic>{
            'email': 'customer@example.com',
            'password': 'secret123',
            'username': 'John Doe',
            'phone': '+2348000000000',
            'address': 'Lagos, Nigeria',
            'lat': 6.5244,
            'lng': 3.3792,
            'referralCode': 'ABC123',
          },
          successCode: 201,
          successDescription: 'Customer created.',
          requiresAuth: false,
        ),
      },
      '/auth/customer/sign_in': <String, dynamic>{
        'post': _operation(
          summary: 'Sign in customer',
          tag: 'Auth',
          requestBodyDescription: 'Customer sign-in payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'email': _stringSchema(description: 'Customer email'),
              'password': _stringSchema(description: 'Customer password'),
            },
            required: const <String>['email', 'password'],
          ),
          requestBodyExample: <String, dynamic>{
            'email': 'customer@example.com',
            'password': 'secret123',
          },
          requiresAuth: false,
        ),
      },
      '/auth/artisan/sign_up': <String, dynamic>{
        'post': _operation(
          summary: 'Sign up artisan',
          tag: 'Auth',
          requestBodyDescription: 'Artisan registration payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(description: 'Artisan name'),
              'email': _stringSchema(description: 'Artisan email'),
              'password': _stringSchema(description: 'Artisan password'),
              'phone': _stringSchema(description: 'Phone number'),
              'address': _stringSchema(description: 'Address'),
              'locationAddress': _stringSchema(description: 'Address alias'),
              'lat': <String, dynamic>{'type': 'number'},
              'lng': <String, dynamic>{'type': 'number'},
              'bio': _stringSchema(description: 'Bio'),
              'title': _stringSchema(description: 'Professional title'),
              'profileImageUrl': _stringSchema(
                description: 'Profile image URL',
              ),
              'skills': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'referralCode': _stringSchema(
                description: 'Optional referral code',
              ),
            },
            required: const <String>['name', 'email', 'password'],
          ),
          requestBodyExample: <String, dynamic>{
            'name': 'Jane Artisan',
            'email': 'artisan@example.com',
            'password': 'secret123',
            'phone': '+2348000000001',
            'locationAddress': 'Abuja, Nigeria',
            'lat': 9.0765,
            'lng': 7.3986,
            'bio': 'I build custom furniture.',
            'title': 'Carpenter',
            'profileImageUrl': 'https://cdn.example.com/avatar.jpg',
            'skills': <String>['woodwork', 'installation'],
            'referralCode': 'ABC123',
          },
          successCode: 201,
          successDescription: 'Artisan created.',
          requiresAuth: false,
        ),
      },
      '/auth/artisan/sign_in': <String, dynamic>{
        'post': _operation(
          summary: 'Sign in artisan',
          tag: 'Auth',
          requestBodyDescription: 'Artisan sign-in payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'email': _stringSchema(description: 'Artisan email'),
              'password': _stringSchema(description: 'Artisan password'),
            },
            required: const <String>['email', 'password'],
          ),
          requestBodyExample: <String, dynamic>{
            'email': 'artisan@example.com',
            'password': 'secret123',
          },
          requiresAuth: false,
        ),
      },
      '/profile': <String, dynamic>{
        'get': _operation(
          summary: 'Get profile',
          tag: 'Profile',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
        ),
        'put': _operation(
          summary: 'Update profile',
          tag: 'Profile',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
          requestBodyDescription:
              'Profile fields to update (JSON or multipart/form-data).',
          requestBodyContent: <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': _objectSchema(
                properties: <String, dynamic>{
                  'username': _stringSchema(),
                  'name': _stringSchema(),
                  'phone': _stringSchema(),
                  'phoneNumber': _stringSchema(),
                  'address': _stringSchema(),
                  'locationAddress': _stringSchema(),
                  'bio': _stringSchema(),
                  'title': _stringSchema(),
                  'profileImage': _stringSchema(),
                  'imageUrl': _stringSchema(),
                  'coverImage': _stringSchema(),
                  'lat': <String, dynamic>{'type': 'number'},
                  'lng': <String, dynamic>{'type': 'number'},
                },
                additionalProperties: true,
              ),
              'example': <String, dynamic>{
                'username': 'Updated Name',
                'phoneNumber': '+2348000000002',
                'address': 'Lekki, Lagos',
                'bio': 'Available on weekdays',
              },
            },
            'multipart/form-data': <String, dynamic>{
              'schema': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'username': _stringSchema(),
                  'name': _stringSchema(),
                  'phone': _stringSchema(),
                  'phoneNumber': _stringSchema(),
                  'address': _stringSchema(),
                  'locationAddress': _stringSchema(),
                  'bio': _stringSchema(),
                  'title': _stringSchema(),
                  'lat': <String, dynamic>{'type': 'number'},
                  'lng': <String, dynamic>{'type': 'number'},
                  'profileImage': <String, dynamic>{
                    'type': 'string',
                    'format': 'binary',
                    'description': 'Profile image file.',
                  },
                  'coverImage': <String, dynamic>{
                    'type': 'string',
                    'format': 'binary',
                    'description': 'Cover image file.',
                  },
                },
                'additionalProperties': true,
              },
            },
          },
        ),
      },
      '/stories': <String, dynamic>{
        'get': _operation(
          summary: 'List stories',
          tag: 'Stories',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'artisanId',
              description: 'Filter by artisan id.',
            ),
            _queryParam(name: 'limit', description: 'Max number of stories.'),
            _queryParam(
              name: 'withinHours',
              description: 'Only stories within N hours.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create story',
          tag: 'Stories',
          requestBodyDescription: 'Story payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'content': _stringSchema(),
              'caption': _stringSchema(),
              'postId': _stringSchema(),
              'imageUrl': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'mediaUrls': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'isAdminPost': <String, dynamic>{'type': 'boolean'},
              'latitude': <String, dynamic>{'type': 'number'},
              'longitude': <String, dynamic>{'type': 'number'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'content': 'New story',
            'imageUrl': <String>['https://cdn.example.com/story.jpg'],
            'postId': 'post_123',
            'isAdminPost': false,
            'latitude': 6.5244,
            'longitude': 3.3792,
          },
          successCode: 201,
          successDescription: 'Story created.',
        ),
      },
      '/stories/vendors': <String, dynamic>{
        'get': _operation(
          summary: 'List story vendors',
          tag: 'Stories',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of vendors.'),
            _queryParam(
              name: 'withinHours',
              description: 'Only active stories within N hours.',
            ),
          ],
        ),
      },
      '/stories/views': <String, dynamic>{
        'get': _operation(
          summary: 'Get viewed story IDs',
          tag: 'Stories',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'storyIds',
              description: 'Comma-separated story IDs.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Mark story viewed',
          tag: 'Stories',
          requestBodyDescription: 'Body containing `storyId`.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'storyId': _stringSchema(),
            },
            required: const <String>['storyId'],
          ),
          requestBodyExample: <String, dynamic>{'storyId': 'story_123'},
        ),
      },
      '/notifications': <String, dynamic>{
        'get': _operation(
          summary: 'List notifications',
          tag: 'Notifications',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
            _queryParam(
              name: 'limit',
              description: 'Max number of notifications.',
            ),
            _queryParam(
              name: 'unreadOnly',
              description: 'Use true for unread only.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create notification',
          tag: 'Notifications',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
          requestBodyDescription: 'Notification payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'body': _stringSchema(),
              'type': _stringSchema(),
              'data': <String, dynamic>{
                'type': 'object',
                'additionalProperties': true,
              },
            },
            required: const <String>['title', 'body'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'title': 'New promo',
            'body': 'Check the new offers near you.',
            'type': 'general',
            'data': <String, dynamic>{'campaignId': 'cmp_001'},
          },
          successCode: 201,
          successDescription: 'Notification created.',
        ),
      },
      '/notifications/read_all': <String, dynamic>{
        'post': _operation(
          summary: 'Mark all notifications as read',
          tag: 'Notifications',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
        ),
      },
      '/notifications/{notification_id}/read': <String, dynamic>{
        'post': _operation(
          summary: 'Mark notification as read',
          tag: 'Notifications',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'notification_id'),
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
        ),
        'patch': _operation(
          summary: 'Mark notification as read (PATCH)',
          tag: 'Notifications',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'notification_id'),
            _queryParam(
              name: 'role',
              description: 'User role (`customer` or `artisan`).',
              required: true,
            ),
          ],
        ),
      },
      '/workfeeds': <String, dynamic>{
        'get': _operation(
          summary: 'List workfeeds',
          tag: 'Workfeeds',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of posts.'),
            _queryParam(
              name: 'artisanId',
              description: 'Filter by artisan id.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create workfeed post',
          tag: 'Workfeeds',
          requestBodyDescription: 'Workfeed post payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'content': _stringSchema(),
              'caption': _stringSchema(),
              'imageUrl': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'mediaUrls': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'isAdminPost': <String, dynamic>{'type': 'boolean'},
              'latitude': <String, dynamic>{'type': 'number'},
              'longitude': <String, dynamic>{'type': 'number'},
              'mirrorToStories': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'content': 'New post from my workshop',
            'imageUrl': <String>['https://cdn.example.com/work-1.jpg'],
            'isAdminPost': false,
            'latitude': 6.5244,
            'longitude': 3.3792,
            'mirrorToStories': true,
          },
          successCode: 201,
          successDescription: 'Post created.',
        ),
      },
      '/workfeeds/{post_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get workfeed post',
          tag: 'Workfeeds',
          parameters: <Map<String, dynamic>>[_pathParam(name: 'post_id')],
        ),
        'delete': _operation(
          summary: 'Delete workfeed post',
          tag: 'Workfeeds',
          parameters: <Map<String, dynamic>>[_pathParam(name: 'post_id')],
        ),
      },
      '/workfeeds/{post_id}/likes': <String, dynamic>{
        'post': _operation(
          summary: 'Toggle post like',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[_pathParam(name: 'post_id')],
        ),
      },
      '/workfeeds/{post_id}/report': <String, dynamic>{
        'post': _operation(
          summary: 'Report post',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[_pathParam(name: 'post_id')],
          requestBodyDescription: 'Post report payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'reason': _stringSchema(),
              'additionalDetails': _stringSchema(),
              'postType': _stringSchema(),
            },
            required: const <String>['reason'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'reason': 'Spam content',
            'additionalDetails': 'Repeated promotional posts.',
            'postType': 'regular',
          },
          successCode: 201,
          successDescription: 'Post report submitted.',
        ),
      },
      '/workfeeds/{post_id}/comments': <String, dynamic>{
        'get': _operation(
          summary: 'List comments',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'post_id'),
            _queryParam(name: 'limit', description: 'Max number of comments.'),
            _queryParam(
              name: 'parentCommentId',
              description: 'Filter replies by parent comment id.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create comment',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[_pathParam(name: 'post_id')],
          requestBodyDescription: 'Comment payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'text': _stringSchema(),
              'parentCommentId': _stringSchema(),
            },
            required: const <String>['text'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'text': 'Nice work!',
            'parentCommentId': 'comment_001',
          },
          successCode: 201,
          successDescription: 'Comment created.',
        ),
      },
      '/workfeeds/{post_id}/comments/{comment_id}/likes': <String, dynamic>{
        'post': _operation(
          summary: 'Toggle comment like',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'post_id'),
            _pathParam(name: 'comment_id'),
          ],
        ),
      },
      '/workfeeds/{post_id}/comments/{comment_id}/report': <String, dynamic>{
        'post': _operation(
          summary: 'Report comment',
          tag: 'Workfeed Engagement',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'post_id'),
            _pathParam(name: 'comment_id'),
          ],
          requestBodyDescription: 'Comment report payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'reason': _stringSchema(),
              'additionalDetails': _stringSchema(),
            },
            required: const <String>['reason'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'reason': 'Harassment',
            'additionalDetails': 'Contains abusive language.',
          },
          successCode: 201,
          successDescription: 'Comment report submitted.',
        ),
      },
      '/chatlist': <String, dynamic>{
        'get': _operation(
          summary: 'List chat rooms (chat list)',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
            _queryParam(
              name: 'limit',
              description: 'Max number of chat rooms.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
            _queryParam(
              name: 'search',
              description: 'Search by peer display name.',
            ),
          ],
        ),
      },
      '/chatlist/pins': <String, dynamic>{
        'get': _operation(
          summary: 'Get pinned chats',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Pin or unpin a chat room',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Pin toggle payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'chatRoomId': _stringSchema(),
              'pinned': <String, dynamic>{'type': 'boolean'},
            },
            required: const <String>['chatRoomId'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'chatRoomId': 'room_123',
            'pinned': true,
          },
        ),
      },
      '/chatlist/unread_count': <String, dynamic>{
        'get': _operation(
          summary: 'Get unread message summary',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
      },
      '/chats': <String, dynamic>{
        'get': _operation(
          summary: 'List chat rooms',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
            _queryParam(
              name: 'limit',
              description: 'Max number of chat rooms.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
            _queryParam(
              name: 'search',
              description: 'Search by peer display name.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create or update chat room',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Chat room payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'chatRoomId': _stringSchema(),
              'otherId': _stringSchema(),
            },
            required: const <String>['chatRoomId', 'otherId'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'chatRoomId': 'room_vendor_01_customer_09',
            'otherId': 'uid_other_user',
          },
        ),
      },
      '/chats/forward': <String, dynamic>{
        'post': _operation(
          summary: 'Forward message to one or more chat rooms',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Forward payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'sourceChatRoomId': _stringSchema(),
              'sourceMessageId': _stringSchema(),
              'targetChatRoomIds': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'sourceMessage': <String, dynamic>{
                'type': 'object',
                'additionalProperties': true,
              },
            },
            required: const <String>['targetChatRoomIds'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'sourceChatRoomId': 'room_123',
            'sourceMessageId': 'm_456',
            'targetChatRoomIds': <String>['room_789', 'room_999'],
          },
        ),
      },
      '/chats/presence': <String, dynamic>{
        'post': _operation(
          summary: 'Set current user presence',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Presence payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'isOnline': <String, dynamic>{'type': 'boolean'},
            },
            required: const <String>['isOnline'],
          ),
          requestBodyExample: <String, dynamic>{'isOnline': true},
        ),
      },
      '/chats/blocked/{user_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get blocked status for user',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'user_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Block a user',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'user_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
        'delete': _operation(
          summary: 'Unblock a user',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'user_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
      },
      '/chats/presence/{user_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get another user presence',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'user_id'),
          ],
        ),
      },
      '/chats/report/{user_id}': <String, dynamic>{
        'post': _operation(
          summary: 'Report a user',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'user_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'User report payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'reason': _stringSchema(),
              'name': _stringSchema(description: 'Optional reported user name'),
              'reporterName': _stringSchema(
                description: 'Optional reporter display name',
              ),
              'additionalDetails': _stringSchema(),
            },
            required: const <String>['reason'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'reason': 'Harassment',
            'additionalDetails': 'User keeps sending abusive messages.',
          },
          successCode: 201,
          successDescription: 'User report submitted.',
        ),
      },
      '/chats/{chat_room_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get chat room',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
        'delete': _operation(
          summary: 'Delete chat room and messages',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
      },
      '/chats/{chat_room_id}/read': <String, dynamic>{
        'post': _operation(
          summary: 'Mark messages as read',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Read acknowledgement payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'otherId': _stringSchema(),
            },
            required: const <String>['otherId'],
          ),
          requestBodyExample: <String, dynamic>{'otherId': 'uid_other_user'},
        ),
      },
      '/chats/{chat_room_id}/status_vote': <String, dynamic>{
        'post': _operation(
          summary: 'Vote project status in chat room',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Status vote payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(
                description: 'Example: accepted, ongoing, completed',
              ),
            },
            required: const <String>['status'],
          ),
          requestBodyExample: <String, dynamic>{'status': 'accepted'},
        ),
      },
      '/chats/{chat_room_id}/messages': <String, dynamic>{
        'get': _operation(
          summary: 'List chat messages',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
            _queryParam(name: 'limit', description: 'Max number of messages.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Send chat message',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Message payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'otherId': _stringSchema(),
              'receiverId': _stringSchema(),
              'text': _stringSchema(),
              'audioUrl': _stringSchema(),
              'audioDuration': <String, dynamic>{'type': 'integer'},
              'imageUrls': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'videoUrls': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
              'isQuoteRequest': <String, dynamic>{'type': 'boolean'},
              'quoteData': <String, dynamic>{
                'type': 'object',
                'additionalProperties': true,
              },
            },
            required: const <String>['otherId'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'otherId': 'uid_other_user',
            'text': 'Hello, are you available tomorrow?',
          },
          successCode: 201,
          successDescription: 'Message sent.',
        ),
      },
      '/chats/{chat_room_id}/messages/{message_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get a message',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _pathParam(name: 'message_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
        ),
        'patch': _operation(
          summary: 'Apply message action or update quote status',
          tag: 'Chats',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'chat_room_id'),
            _pathParam(name: 'message_id'),
            _queryParam(
              name: 'role',
              description: 'Role hint: customer|vendor|artisan.',
            ),
          ],
          requestBodyDescription: 'Message action payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'action': _stringSchema(
                description:
                    'add_reaction | mark_audio_played | delete_for_me | delete_for_everyone | update_quote_status',
              ),
              'emoji': _stringSchema(),
              'status': _stringSchema(
                description: 'Used when action=update_quote_status',
              ),
            },
            required: const <String>['action'],
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'action': 'add_reaction',
            'emoji': ':thumbs_up:',
          },
        ),
      },
      '/vendors': <String, dynamic>{
        'get': _operation(
          summary: 'Discover vendors',
          tag: 'Vendors',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of vendors.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
            _queryParam(
              name: 'location',
              description: 'Location text or "lat,lng".',
            ),
            _queryParam(
              name: 'latitude',
              description: 'Latitude for geo search.',
            ),
            _queryParam(
              name: 'longitude',
              description: 'Longitude for geo search.',
            ),
            _queryParam(name: 'radiusKm', description: 'Radius in kilometers.'),
            _queryParam(
              name: 'skills',
              description: 'Comma-separated skills filter.',
            ),
            _queryParam(
              name: 'searchBySkills',
              description: 'Alias for skills filter.',
            ),
            _queryParam(name: 'name', description: 'Vendor name/title search.'),
            _queryParam(
              name: 'premium',
              description: 'Premium filter (true/false).',
            ),
          ],
        ),
      },
      '/vendors/{vendor_id}/portfolio': <String, dynamic>{
        'get': _operation(
          summary: 'Get vendor portfolio media',
          tag: 'Vendors',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'vendor_id'),
            _queryParam(
              name: 'limit',
              description: 'Max number of portfolio media items.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
      },
      '/vendors/{vendor_id}/reviews': <String, dynamic>{
        'get': _operation(
          summary: 'Get vendor reviews',
          tag: 'Vendors',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'vendor_id'),
            _queryParam(name: 'limit', description: 'Max number of reviews.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
      },
      '/vendors/{vendor_id}/workfeeds': <String, dynamic>{
        'get': _operation(
          summary: 'Get vendor workfeed posts',
          tag: 'Vendors',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'vendor_id'),
            _queryParam(
              name: 'limit',
              description: 'Max number of workfeed posts.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
      },
      '/products': <String, dynamic>{
        'get': _operation(
          summary: 'List products',
          tag: 'Commerce',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of products.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
            _queryParam(name: 'shopId', description: 'Filter by shop id.'),
            _queryParam(name: 'ownerId', description: 'Filter by owner id.'),
            _queryParam(name: 'category', description: 'Filter by category.'),
            _queryParam(name: 'search', description: 'Search text.'),
            _queryParam(name: 'active', description: 'Filter by active state.'),
            _queryParam(name: 'minPrice', description: 'Minimum price.'),
            _queryParam(name: 'maxPrice', description: 'Maximum price.'),
          ],
        ),
        'post': _operation(
          summary: 'Create product',
          tag: 'Commerce',
          requestBodyDescription: 'Product payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'shopId': _stringSchema(),
              'ownerId': _stringSchema(),
              'category': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'title': 'Wall Paint',
            'price': 4500,
            'shopId': 'shop_123',
            'ownerId': 'uid_merchant',
            'category': 'paint',
          },
          successCode: 201,
          successDescription: 'Product created.',
        ),
      },
      '/products/{product_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get product',
          tag: 'Commerce',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'product_id'),
          ],
        ),
        'patch': _operation(
          summary: 'Update product',
          tag: 'Commerce',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'product_id'),
          ],
          requestBodyDescription: 'Product update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'category': _stringSchema(),
              'active': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'price': 5000,
            'active': true,
          },
        ),
        'delete': _operation(
          summary: 'Delete product',
          tag: 'Commerce',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'product_id'),
          ],
        ),
      },
      '/products/{shop}/{category}': <String, dynamic>{
        'get': _operation(
          summary: 'List products by shop and category',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
          ],
        ),
        'post': _operation(
          summary: 'Create product in shop/category',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
          ],
          requestBodyDescription: 'Product payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'name': 'Satin Paint 4L',
            'price': 12000,
          },
          successCode: 201,
          successDescription: 'Product created.',
        ),
      },
      '/products/{shop}/{category}/{product_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get shop/category product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
            _pathParam(name: 'product_id'),
          ],
        ),
        'put': _operation(
          summary: 'Replace shop/category product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
            _pathParam(name: 'product_id'),
          ],
          requestBodyDescription: 'Full product payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'name': 'Satin Paint 4L',
            'price': 12000,
            'imageUrl': 'https://cdn.example.com/p-1.jpg',
          },
        ),
        'patch': _operation(
          summary: 'Update shop/category product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
            _pathParam(name: 'product_id'),
          ],
          requestBodyDescription: 'Partial product update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'price': 12500},
        ),
        'delete': _operation(
          summary: 'Delete shop/category product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'shop'),
            _pathParam(name: 'category'),
            _pathParam(name: 'product_id'),
          ],
        ),
      },
      '/news': <String, dynamic>{
        'get': _operation(
          summary: 'List news',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'limit',
              description: 'Max number of news items.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
            _queryParam(name: 'screen', description: 'Optional screen filter.'),
          ],
        ),
        'post': _operation(
          summary: 'Create news',
          tag: 'Legacy',
          requestBodyDescription: 'News payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'body': _stringSchema(),
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'title': 'Weekly Update',
            'body': 'New products available this week.',
          },
          successCode: 201,
          successDescription: 'News item created.',
        ),
      },
      '/news/{news_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get news item',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'news_id'),
          ],
        ),
        'patch': _operation(
          summary: 'Update news item',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'news_id'),
          ],
          requestBodyDescription: 'News update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'body': _stringSchema(),
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'title': 'Updated headline'},
        ),
        'delete': _operation(
          summary: 'Delete news item',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'news_id'),
          ],
        ),
      },
      '/appMessages': <String, dynamic>{
        'get': _operation(
          summary: 'List app messages',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _queryParam(
              name: 'limit',
              description: 'Max number of app messages.',
            ),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create app message',
          tag: 'Legacy',
          requestBodyDescription:
              'App message payload (JSON or multipart/form-data).',
          requestBodyContent: <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': _objectSchema(
                properties: <String, dynamic>{
                  'title': _stringSchema(),
                  'body': _stringSchema(),
                  'messageText': _stringSchema(),
                  'type': _stringSchema(),
                  'imageUrl': _stringSchema(),
                },
                additionalProperties: true,
              ),
              'example': <String, dynamic>{
                'title': 'Maintenance Notice',
                'messageText': 'Select Location',
                'body': 'The app will be down for maintenance at midnight.',
              },
            },
            'multipart/form-data': <String, dynamic>{
              'schema': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'title': _stringSchema(),
                  'body': _stringSchema(),
                  'messageText': _stringSchema(),
                  'type': _stringSchema(),
                  'image': <String, dynamic>{
                    'type': 'string',
                    'format': 'binary',
                    'description':
                        'Image file to upload; server returns imageUrl.',
                  },
                },
                'additionalProperties': true,
              },
            },
          },
          successCode: 201,
          successDescription: 'App message created.',
        ),
      },
      '/appMessages/{message_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get app message',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'message_id'),
          ],
        ),
        'patch': _operation(
          summary: 'Update app message',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'message_id'),
          ],
          requestBodyDescription:
              'App message update payload (JSON or multipart/form-data).',
          requestBodyContent: <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': _objectSchema(
                properties: <String, dynamic>{
                  'title': _stringSchema(),
                  'body': _stringSchema(),
                  'messageText': _stringSchema(),
                  'type': _stringSchema(),
                  'imageUrl': _stringSchema(),
                },
                additionalProperties: true,
              ),
              'example': <String, dynamic>{
                'messageText': 'Updated copy',
              },
            },
            'multipart/form-data': <String, dynamic>{
              'schema': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'title': _stringSchema(),
                  'body': _stringSchema(),
                  'messageText': _stringSchema(),
                  'type': _stringSchema(),
                  'image': <String, dynamic>{
                    'type': 'string',
                    'format': 'binary',
                    'description':
                        'Image file to upload; server returns imageUrl.',
                  },
                },
                'additionalProperties': true,
              },
            },
          },
        ),
        'delete': _operation(
          summary: 'Delete app message',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'message_id'),
          ],
        ),
      },
      '/userFavorites/{uid}': <String, dynamic>{
        'get': _operation(
          summary: 'Get user favorites',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
          ],
        ),
      },
      '/userFavorites/{uid}/{product_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get user favorite product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'product_id'),
          ],
        ),
        'put': _operation(
          summary: 'Replace user favorite product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'product_id'),
          ],
          requestBodyDescription: 'Favorite payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'name': 'Favorite product',
            'price': 1500,
          },
        ),
        'patch': _operation(
          summary: 'Update user favorite product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'product_id'),
          ],
          requestBodyDescription: 'Favorite update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'name': _stringSchema(),
              'price': <String, dynamic>{'type': 'number'},
              'imageUrl': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'price': 1600},
        ),
        'delete': _operation(
          summary: 'Delete user favorite product',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'product_id'),
          ],
        ),
      },
      '/admin/orders': <String, dynamic>{
        'get': _operation(
          summary: 'List admin orders',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'status', description: 'Optional status filter.'),
          ],
        ),
        'post': _operation(
          summary: 'Create admin order',
          tag: 'Legacy',
          requestBodyDescription: 'Order payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
              'customerId': _stringSchema(),
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'status': 'pending',
            'amount': 25000,
          },
          successCode: 201,
          successDescription: 'Admin order created.',
        ),
      },
      '/admin/orders/{order_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get admin order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'order_id'),
          ],
        ),
        'put': _operation(
          summary: 'Replace admin order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'order_id'),
          ],
          requestBodyDescription: 'Order payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'status': 'paid'},
        ),
        'patch': _operation(
          summary: 'Update admin order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'order_id'),
          ],
          requestBodyDescription: 'Order update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'status': 'shipped'},
        ),
        'delete': _operation(
          summary: 'Delete admin order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'order_id'),
          ],
        ),
      },
      '/{uid}/orders': <String, dynamic>{
        'get': _operation(
          summary: 'List user orders',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _queryParam(name: 'status', description: 'Optional status filter.'),
          ],
        ),
        'post': _operation(
          summary: 'Create user order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
          ],
          requestBodyDescription: 'Order payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
              'items': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'object',
                  'additionalProperties': true,
                },
              },
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'status': 'pending',
            'amount': 16000,
          },
          successCode: 201,
          successDescription: 'User order created.',
        ),
      },
      '/{uid}/orders/{order_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get user order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'order_id'),
          ],
        ),
        'put': _operation(
          summary: 'Replace user order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'order_id'),
          ],
          requestBodyDescription: 'Order payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'status': 'completed'},
        ),
        'patch': _operation(
          summary: 'Update user order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'order_id'),
          ],
          requestBodyDescription: 'Order update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'status': _stringSchema(),
              'amount': <String, dynamic>{'type': 'number'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'status': 'cancelled'},
        ),
        'delete': _operation(
          summary: 'Delete user order',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'uid'),
            _pathParam(name: 'order_id'),
          ],
        ),
      },
      '/promo/promo/promos': <String, dynamic>{
        'get': _operation(
          summary: 'List legacy promos (promo/promo/promos)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of promos.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create legacy promo (promo/promo/promos)',
          tag: 'Legacy',
          requestBodyDescription: 'Promo payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'description': _stringSchema(),
              'active': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'title': 'Easter Discount',
            'description': 'Get 10% off',
            'active': true,
          },
          successCode: 201,
          successDescription: 'Promo created.',
        ),
      },
      '/promo/promo/promos/{promo_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get legacy promo (promo/promo/promos)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
        ),
        'patch': _operation(
          summary: 'Update legacy promo (promo/promo/promos)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
          requestBodyDescription: 'Promo update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'description': _stringSchema(),
              'active': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'active': false},
        ),
        'delete': _operation(
          summary: 'Delete legacy promo (promo/promo/promos)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
        ),
      },
      '/promo/Admin/Admin': <String, dynamic>{
        'get': _operation(
          summary: 'List legacy promos (promo/Admin/Admin)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _queryParam(name: 'limit', description: 'Max number of promos.'),
            _queryParam(
              name: 'pageToken',
              description: 'Pagination cursor token.',
            ),
          ],
        ),
        'post': _operation(
          summary: 'Create legacy promo (promo/Admin/Admin)',
          tag: 'Legacy',
          requestBodyDescription: 'Promo payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'description': _stringSchema(),
              'active': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{
            'title': 'Featured Promo',
            'description': 'Top placement this week',
            'active': true,
          },
          successCode: 201,
          successDescription: 'Promo created.',
        ),
      },
      '/promo/Admin/Admin/{promo_id}': <String, dynamic>{
        'get': _operation(
          summary: 'Get legacy promo (promo/Admin/Admin)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
        ),
        'patch': _operation(
          summary: 'Update legacy promo (promo/Admin/Admin)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
          requestBodyDescription: 'Promo update payload.',
          requestBodySchema: _objectSchema(
            properties: <String, dynamic>{
              'title': _stringSchema(),
              'description': _stringSchema(),
              'active': <String, dynamic>{'type': 'boolean'},
            },
            additionalProperties: true,
          ),
          requestBodyExample: <String, dynamic>{'active': false},
        ),
        'delete': _operation(
          summary: 'Delete legacy promo (promo/Admin/Admin)',
          tag: 'Legacy',
          parameters: <Map<String, dynamic>>[
            _pathParam(name: 'promo_id'),
          ],
        ),
      },
    },
  };
}

Map<String, dynamic> _operation({
  required String summary,
  required String tag,
  List<Map<String, dynamic>>? parameters,
  String? requestBodyDescription,
  Map<String, dynamic>? requestBodySchema,
  Map<String, dynamic>? requestBodyExample,
  Map<String, dynamic>? requestBodyContent,
  int successCode = 200,
  String successDescription = 'Success',
  bool requiresAuth = true,
}) {
  final responses = <String, dynamic>{
    '$successCode': <String, dynamic>{
      'description': successDescription,
      'content': <String, dynamic>{
        'application/json': <String, dynamic>{
          'schema': <String, dynamic>{
            'type': 'object',
            'additionalProperties': true,
          },
        },
      },
    },
    '400': _errorResponse('Bad request'),
    '401': _errorResponse('Unauthorized'),
    '403': _errorResponse('Forbidden'),
    '404': _errorResponse('Not found'),
    '500': _errorResponse('Unexpected server error'),
  };

  return <String, dynamic>{
    'tags': <String>[tag],
    'summary': summary,
    if (requiresAuth)
      'security': <Map<String, dynamic>>[
        <String, dynamic>{'bearerAuth': <String>[]},
      ],
    if (parameters != null && parameters.isNotEmpty) 'parameters': parameters,
    if (requestBodyDescription != null &&
        (requestBodySchema != null || requestBodyContent != null))
      'requestBody': <String, dynamic>{
        'required': true,
        'description': requestBodyDescription,
        'content': <String, dynamic>{
          ...?requestBodyContent,
          if (requestBodyContent == null)
            'application/json': <String, dynamic>{
              'schema': requestBodySchema,
              if (requestBodyExample != null) 'example': requestBodyExample,
            },
        }..removeWhere((_, value) => value == null),
      },
    'responses': responses,
  };
}

Map<String, dynamic> _queryParam({
  required String name,
  required String description,
  bool required = false,
}) {
  return <String, dynamic>{
    'name': name,
    'in': 'query',
    'required': required,
    'description': description,
    'schema': <String, dynamic>{'type': 'string'},
  };
}

Map<String, dynamic> _pathParam({
  required String name,
}) {
  return <String, dynamic>{
    'name': name,
    'in': 'path',
    'required': true,
    'schema': <String, dynamic>{'type': 'string'},
  };
}

Map<String, dynamic> _errorResponse(String description) {
  return <String, dynamic>{
    'description': description,
    'content': <String, dynamic>{
      'application/json': <String, dynamic>{
        'schema': <String, dynamic>{
          r'$ref': '#/components/schemas/Error',
        },
      },
    },
  };
}

Map<String, dynamic> _objectSchema({
  required Map<String, dynamic> properties,
  List<String>? required,
  bool additionalProperties = false,
}) {
  return <String, dynamic>{
    'type': 'object',
    'properties': properties,
    if (required != null && required.isNotEmpty) 'required': required,
    'additionalProperties': additionalProperties,
  };
}

Map<String, dynamic> _stringSchema({String? description}) {
  return <String, dynamic>{
    'type': 'string',
    if (description != null) 'description': description,
  };
}
