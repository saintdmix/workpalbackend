import 'package:test/test.dart';
import 'package:workpalbackend/src/utils/notification_types.dart';

void main() {
  group('canonicalizeNotificationType', () {
    test('returns canonical values for supported types', () {
      expect(
        canonicalizeNotificationType(notificationTypeJobApplication),
        notificationTypeJobApplication,
      );
      expect(
        canonicalizeNotificationType(notificationTypePromoPostTap),
        notificationTypePromoPostTap,
      );
    });

    test('normalizes aliases and spaced input', () {
      expect(
        canonicalizeNotificationType('job update'),
        notificationTypeJobApplication,
      );
      expect(
        canonicalizeNotificationType('chat-message'),
        notificationTypeChatMessage,
      );
      expect(
        canonicalizeNotificationType('comment reply'),
        notificationTypeCommentReply,
      );
      expect(
        canonicalizeNotificationType('promoted post tap'),
        notificationTypePromoPostTap,
      );
    });

    test('returns null for unsupported types', () {
      expect(canonicalizeNotificationType('not_real'), isNull);
    });
  });
}
