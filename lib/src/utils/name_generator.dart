import 'dart:convert';
import '../config/identity_ui_config.dart';

/// Generates deterministic human-readable names from cryptographic keys
class NameGenerator {
  // Word lists for generating memorable names
  static const List<String> adjectives = [
    'Swift',
    'Bright',
    'Calm',
    'Bold',
    'Wise',
    'Kind',
    'Brave',
    'Quick',
    'Silent',
    'Noble',
    'Gentle',
    'Fierce',
    'Clever',
    'Proud',
    'Loyal',
    'Wild',
    'Ancient',
    'Golden',
    'Silver',
    'Crystal',
    'Mystic',
    'Sacred',
    'Royal',
    'Grand',
    'Mighty',
    'Cosmic',
    'Stellar',
    'Lunar',
    'Solar',
    'Arctic',
    'Tropic',
    'Azure',
    'Crimson',
    'Emerald',
    'Amber',
    'Jade',
    'Ruby',
    'Pearl',
    'Onyx',
    'Topaz',
    'Sapphire',
    'Diamond',
    'Platinum',
    'Titanium',
    'Iron',
    'Steel',
    'Bronze',
    'Copper',
    'Thunder',
    'Storm',
    'Cloud',
    'Rain',
    'Snow',
    'Frost',
    'Blaze',
    'Flame',
    'Ocean',
    'River',
    'Mountain',
    'Forest',
    'Desert',
    'Valley',
    'Canyon',
    'Peak',
  ];

  static const List<String> nouns = [
    'Phoenix',
    'Dragon',
    'Tiger',
    'Eagle',
    'Wolf',
    'Bear',
    'Lion',
    'Hawk',
    'Falcon',
    'Raven',
    'Owl',
    'Fox',
    'Lynx',
    'Panther',
    'Leopard',
    'Jaguar',
    'Dolphin',
    'Whale',
    'Shark',
    'Orca',
    'Seal',
    'Otter',
    'Penguin',
    'Albatross',
    'Warrior',
    'Knight',
    'Guardian',
    'Sentinel',
    'Ranger',
    'Scout',
    'Hunter',
    'Seeker',
    'Voyager',
    'Explorer',
    'Pioneer',
    'Wanderer',
    'Nomad',
    'Traveler',
    'Pilgrim',
    'Wayfarer',
    'Star',
    'Comet',
    'Meteor',
    'Nova',
    'Nebula',
    'Galaxy',
    'Cosmos',
    'Quasar',
    'Thunder',
    'Lightning',
    'Storm',
    'Tempest',
    'Cyclone',
    'Typhoon',
    'Hurricane',
    'Tornado',
    'Sage',
    'Oracle',
    'Prophet',
    'Mystic',
    'Wizard',
    'Sorcerer',
    'Mage',
    'Enchanter',
  ];

  /// Generate a deterministic human-readable name from a base64-encoded key
  /// Same key always produces the same name
  static String generateName(String base64Key) {
    try {
      // Decode base64 to bytes
      final bytes = base64.decode(base64Key);
      if (bytes.length < 10) return IdentityUiConfig.defaultDisplayName;

      // Use first 4 bytes for adjective selection
      final adjectiveIndex =
          _bytesToInt(bytes.sublist(0, 4)) % adjectives.length;

      // Use next 4 bytes for noun selection
      final nounIndex = _bytesToInt(bytes.sublist(4, 8)) % nouns.length;

      // Use next 2 bytes for number (0-999)
      final number = _bytesToInt(bytes.sublist(8, 10)) % 1000;

      return '${adjectives[adjectiveIndex]} ${nouns[nounIndex]} $number';
    } catch (e) {
      // Fallback if key is invalid
      return IdentityUiConfig.defaultDisplayName;
    }
  }

  /// Generate a short version (without number) for compact display
  static String generateShortName(String base64Key) {
    try {
      final bytes = base64.decode(base64Key);
      if (bytes.length < 8) return 'User';
      final adjectiveIndex =
          _bytesToInt(bytes.sublist(0, 4)) % adjectives.length;
      final nounIndex = _bytesToInt(bytes.sublist(4, 8)) % nouns.length;
      return '${adjectives[adjectiveIndex]} ${nouns[nounIndex]}';
    } catch (e) {
      return 'User';
    }
  }

  /// Get initials from generated name (e.g., "Swift Phoenix" -> "SP")
  static String generateInitials(String base64Key) {
    try {
      final bytes = base64.decode(base64Key);
      if (bytes.length < 8) return 'U';
      final adjectiveIndex =
          _bytesToInt(bytes.sublist(0, 4)) % adjectives.length;
      final nounIndex = _bytesToInt(bytes.sublist(4, 8)) % nouns.length;
      return '${adjectives[adjectiveIndex][0]}${nouns[nounIndex][0]}';
    } catch (e) {
      return 'U';
    }
  }

  /// Convert bytes to integer for indexing
  static int _bytesToInt(List<int> bytes) {
    int result = 0;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | bytes[i];
    }
    return result.abs();
  }

  /// Get a color based on the key (for avatar backgrounds)
  static int getColorFromKey(String base64Key) {
    try {
      final bytes = base64.decode(base64Key);
      if (bytes.length < 13) return 0xFF9E9E9E;
      final colorIndex = _bytesToInt(bytes.sublist(10, 13));

      // Generate a pleasant color palette
      final colors = [
        0xFF2196F3, // Blue
        0xFF4CAF50, // Green
        0xFFF44336, // Red
        0xFFFF9800, // Orange
        0xFF9C27B0, // Purple
        0xFF00BCD4, // Cyan
        0xFFFFEB3B, // Yellow
        0xFFE91E63, // Pink
        0xFF3F51B5, // Indigo
        0xFF009688, // Teal
        0xFFFF5722, // Deep Orange
        0xFF8BC34A, // Light Green
      ];

      return colors[colorIndex % colors.length];
    } catch (e) {
      return 0xFF9E9E9E; // Grey fallback
    }
  }
}
