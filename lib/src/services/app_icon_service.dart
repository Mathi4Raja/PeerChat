import 'dart:typed_data';
import 'dart:collection';
import 'battery_status_service.dart';

/// Expert service implementing an LRU cache for native app icons.
/// Uses a budget of 50 icons (expandable to 75) to minimize memory pressure.
class AppIconService {
  final DeviceSystemService _deviceService;
  final int cacheLimit;
  
  // LRU Cache: LinkedHashMap maintains insertion order
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap<String, Uint8List>();
  final Set<String> _pending = {};

  AppIconService(this._deviceService, {this.cacheLimit = 50});

  /// Fetches an icon with LRU caching.
  /// Returns null if not cached or currently fetching.
  /// If null, the UI should show a placeholder and caller should call 'loadIcon'.
  Uint8List? getIcon(String packageName) {
    if (_cache.containsKey(packageName)) {
      // Move to end (most recently used)
      final icon = _cache.remove(packageName)!;
      _cache[packageName] = icon;
      return icon;
    }
    return null;
  }

  /// Non-blocking load of an icon into the cache.
  Future<void> loadIcon(String packageName, Function() onLoaded) async {
    if (_cache.containsKey(packageName) || _pending.contains(packageName)) return;

    _pending.add(packageName);
    try {
      final iconBytes = await _deviceService.getAppIcon(packageName);
      if (iconBytes != null) {
        _addToCache(packageName, iconBytes);
        onLoaded();
      }
    } finally {
      _pending.remove(packageName);
    }
  }

  void _addToCache(String key, Uint8List value) {
    if (_cache.length >= cacheLimit) {
      // Evict least recently used (first item in LinkedHashMap)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  void clearCache() {
    _cache.clear();
  }
}
