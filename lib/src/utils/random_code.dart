// Place in: lib/src/utils/random_code.dart
import 'dart:math';

String generateRandomCode({int length = 7}) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random();
  return String.fromCharCodes(
    Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
  );
}
