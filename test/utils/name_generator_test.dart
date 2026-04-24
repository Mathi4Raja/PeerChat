import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/config/identity_ui_config.dart';
import 'package:peerchat_secure/src/utils/name_generator.dart';

void main() {
  group('NameGenerator', () {
    final validKey = base64Encode(List<int>.generate(16, (i) => i + 1));

    test('generateName is deterministic for same key', () {
      final a = NameGenerator.generateName(validKey);
      final b = NameGenerator.generateName(validKey);
      expect(a, b);
      expect(a, isNot(IdentityUiConfig.defaultDisplayName));
    });

    test('generateShortName and initials are deterministic', () {
      final shortA = NameGenerator.generateShortName(validKey);
      final shortB = NameGenerator.generateShortName(validKey);
      final initialsA = NameGenerator.generateInitials(validKey);
      final initialsB = NameGenerator.generateInitials(validKey);
      expect(shortA, shortB);
      expect(initialsA, initialsB);
      expect(initialsA.length, 2);
    });

    test('invalid base64 falls back to safe defaults', () {
      expect(
        NameGenerator.generateName('%%%'),
        IdentityUiConfig.defaultDisplayName,
      );
      expect(NameGenerator.generateShortName('%%%'), 'User');
      expect(NameGenerator.generateInitials('%%%'), 'U');
      expect(NameGenerator.getColorFromKey('%%%'), 0xFF9E9E9E);
    });

    test('getColorFromKey is deterministic for valid key', () {
      final c1 = NameGenerator.getColorFromKey(validKey);
      final c2 = NameGenerator.getColorFromKey(validKey);
      expect(c1, c2);
    });
  });
}

