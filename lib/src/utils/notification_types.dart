// ignore_for_file: public_member_api_docs

const notificationTypeGeneral = 'general';
const notificationTypeJobApplication = 'job_application';
const notificationTypeJobAccepted = 'job_accepted';
const notificationTypeJobRejected = 'job_rejected';
const notificationTypeSubscriptionRenewal = 'subscription_renewal';
const notificationTypeChatMessage = 'chat_message';
const notificationTypePostLike = 'post_like';
const notificationTypePostComment = 'post_comment';
const notificationTypeCommentReply = 'comment_reply';
const notificationTypeFollow = 'follow';
const notificationTypeAdminPost = 'admin_post';
const notificationTypePostCreated = 'post_created';
const notificationTypePromoPostTap = 'promo_post_tap';

const notificationTypeValues = <String>[
  notificationTypeGeneral,
  notificationTypeJobApplication,
  notificationTypeJobAccepted,
  notificationTypeJobRejected,
  notificationTypeSubscriptionRenewal,
  notificationTypeChatMessage,
  notificationTypePostLike,
  notificationTypePostComment,
  notificationTypeCommentReply,
  notificationTypeFollow,
  notificationTypeAdminPost,
  notificationTypePostCreated,
  notificationTypePromoPostTap,
];

const notificationTypeDefinitions = <Map<String, String>>[
  <String, String>{
    'value': notificationTypeGeneral,
    'label': 'General',
    'description': 'Fallback notification for any uncategorized event.',
  },
  <String, String>{
    'value': notificationTypeJobApplication,
    'label': 'Job Application',
    'description': 'Tell a customer that someone applied for their job.',
  },
  <String, String>{
    'value': notificationTypeJobAccepted,
    'label': 'Job Accepted',
    'description': 'Tell an artisan that their job or quote was accepted.',
  },
  <String, String>{
    'value': notificationTypeJobRejected,
    'label': 'Job Rejected',
    'description': 'Tell an artisan that their job or quote was rejected.',
  },
  <String, String>{
    'value': notificationTypeSubscriptionRenewal,
    'label': 'Subscription Renewal',
    'description':
        'Tell a user that a subscription was renewed or needs attention.',
  },
  <String, String>{
    'value': notificationTypeChatMessage,
    'label': 'Chat Message',
    'description': 'Tell a user they received a new chat message.',
  },
  <String, String>{
    'value': notificationTypePostLike,
    'label': 'Post Like',
    'description': 'Tell a user that someone liked their post.',
  },
  <String, String>{
    'value': notificationTypePostComment,
    'label': 'Post Comment',
    'description': 'Tell a user that someone commented on their post.',
  },
  <String, String>{
    'value': notificationTypeCommentReply,
    'label': 'Comment Reply',
    'description': 'Tell a user that someone replied to their comment.',
  },
  <String, String>{
    'value': notificationTypeFollow,
    'label': 'Follow',
    'description': 'Tell a user that someone started following them.',
  },
  <String, String>{
    'value': notificationTypeAdminPost,
    'label': 'Admin Post',
    'description': 'Tell users that an admin post was published.',
  },
  <String, String>{
    'value': notificationTypePostCreated,
    'label': 'Post Created',
    'description':
        'Use when a post creation event itself should create a notification.',
  },
  <String, String>{
    'value': notificationTypePromoPostTap,
    'label': 'Promo Post Tap',
    'description': 'Tell a promoter that someone tapped a promoted post.',
  },
];

const _notificationTypeLabels = <String, String>{
  notificationTypeGeneral: 'General',
  notificationTypeJobApplication: 'Job Application',
  notificationTypeJobAccepted: 'Job Accepted',
  notificationTypeJobRejected: 'Job Rejected',
  notificationTypeSubscriptionRenewal: 'Subscription Renewal',
  notificationTypeChatMessage: 'Chat Message',
  notificationTypePostLike: 'Post Like',
  notificationTypePostComment: 'Post Comment',
  notificationTypeCommentReply: 'Comment Reply',
  notificationTypeFollow: 'Follow',
  notificationTypeAdminPost: 'Admin Post',
  notificationTypePostCreated: 'Post Created',
  notificationTypePromoPostTap: 'Promo Post Tap',
};

const _notificationTypeDescriptions = <String, String>{
  notificationTypeGeneral: 'Fallback notification for any uncategorized event.',
  notificationTypeJobApplication:
      'Tell a customer that someone applied for their job.',
  notificationTypeJobAccepted:
      'Tell an artisan that their job or quote was accepted.',
  notificationTypeJobRejected:
      'Tell an artisan that their job or quote was rejected.',
  notificationTypeSubscriptionRenewal:
      'Tell a user that a subscription was renewed or needs attention.',
  notificationTypeChatMessage: 'Tell a user they received a new chat message.',
  notificationTypePostLike: 'Tell a user that someone liked their post.',
  notificationTypePostComment:
      'Tell a user that someone commented on their post.',
  notificationTypeCommentReply:
      'Tell a user that someone replied to their comment.',
  notificationTypeFollow: 'Tell a user that someone started following them.',
  notificationTypeAdminPost: 'Tell users that an admin post was published.',
  notificationTypePostCreated:
      'Use when a post creation event itself should create a notification.',
  notificationTypePromoPostTap:
      'Tell a promoter that someone tapped a promoted post.',
};

const _notificationTypeAliases = <String, String>{
  'job_update': notificationTypeJobApplication,
  'job_applied': notificationTypeJobApplication,
  'job_application': notificationTypeJobApplication,
  'jobaccepted': notificationTypeJobAccepted,
  'job_accepted': notificationTypeJobAccepted,
  'jobrejected': notificationTypeJobRejected,
  'job_rejected': notificationTypeJobRejected,
  'subscription': notificationTypeSubscriptionRenewal,
  'subscription_renewed': notificationTypeSubscriptionRenewal,
  'subscription_renewal': notificationTypeSubscriptionRenewal,
  'chat': notificationTypeChatMessage,
  'message': notificationTypeChatMessage,
  'chat_message': notificationTypeChatMessage,
  'like': notificationTypePostLike,
  'post_like': notificationTypePostLike,
  'comment': notificationTypePostComment,
  'post_comment': notificationTypePostComment,
  'reply': notificationTypeCommentReply,
  'comment_reply': notificationTypeCommentReply,
  'follow_notification': notificationTypeFollow,
  'follower': notificationTypeFollow,
  'follow': notificationTypeFollow,
  'admin_post': notificationTypeAdminPost,
  'post_created': notificationTypePostCreated,
  'new_post': notificationTypePostCreated,
  'workfeed_post': notificationTypePostCreated,
  'promo_tap': notificationTypePromoPostTap,
  'promoted_post_tap': notificationTypePromoPostTap,
  'promo_post_tap': notificationTypePromoPostTap,
  'ad_tap': notificationTypePromoPostTap,
};

String? canonicalizeNotificationType(String? rawType) {
  if (rawType == null || rawType.trim().isEmpty) return null;

  final normalized = rawType
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_')
      .replaceAll(RegExp('_+'), '_');

  if (notificationTypeValues.contains(normalized)) {
    return normalized;
  }

  return _notificationTypeAliases[normalized];
}

String notificationTypeLabel(String type) {
  return _notificationTypeLabels[type] ??
      _notificationTypeLabels[notificationTypeGeneral]!;
}

String notificationTypeDescription(String type) {
  return _notificationTypeDescriptions[type] ??
      _notificationTypeDescriptions[notificationTypeGeneral]!;
}

String notificationTypeValuesText() => notificationTypeValues.join(', ');
