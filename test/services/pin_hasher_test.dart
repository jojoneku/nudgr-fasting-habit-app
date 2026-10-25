import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/pin_verifier.dart';
import 'package:intermittent_fasting/services/app_lock/pin_hasher.dart';

void main() {
  final hasher = PinHasher(iterations: 1000, offThread: false);

  test('a hashed PIN verifies, a different PIN does not', () async {
    final verifier = await hasher.hash('482916');
    expect(await hasher.verify('482916', verifier), isTrue);
    expect(await hasher.verify('482917', verifier), isFalse);
    expect(await hasher.verify('4829', verifier), isFalse);
  });

  test('the stored record never contains the PIN', () async {
    final verifier = await hasher.hash('482916');
    expect(verifier.encode(), isNot(contains('482916')));
    expect(verifier.salt, hasLength(PinHasher.saltBytes));
    expect(verifier.length, 6);
    expect(verifier.iterations, 1000);
  });

  test('the same PIN gets a different salt and hash each time', () async {
    final a = await hasher.hash('1234');
    final b = await hasher.hash('1234');
    expect(a.salt, isNot(b.salt));
    expect(a.hash, isNot(b.hash));
  });

  test('verify honours the iteration count stored with the hash', () async {
    final verifier =
        await PinHasher(iterations: 500, offThread: false).hash('1234');
    expect(await hasher.verify('1234', verifier), isTrue);
  });

  test('only 4 or 6 digits are PINs', () {
    expect(PinHasher.isValidPin('1234'), isTrue);
    expect(PinHasher.isValidPin('123456'), isTrue);
    expect(PinHasher.isValidPin('12345'), isFalse);
    expect(PinHasher.isValidPin('12a4'), isFalse);
    expect(PinHasher.isValidPin(''), isFalse);
    expect(() => hasher.hash('12345'), throwsArgumentError);
  });

  test('an unknown algorithm never verifies', () async {
    final v = await hasher.hash('1234');
    final other = PinVerifier(
      algorithm: 'argon2id',
      iterations: v.iterations,
      salt: v.salt,
      hash: v.hash,
      length: v.length,
    );
    expect(await hasher.verify('1234', other), isFalse);
  });

  test('constantTimeEquals', () {
    expect(PinHasher.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(PinHasher.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(PinHasher.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}
