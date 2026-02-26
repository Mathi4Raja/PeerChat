/// Network discovery and service identity constants.
class NetworkConfig {
  /// TCP port used for local mDNS/NSD service advertising and discovery.
  static const int discoveryPort = 9000;

  /// Service type advertised through mDNS/NSD.
  static const String mdnsServiceType = '_peerchat._tcp';

  /// Fully-qualified service pointer query used for discovery lookups.
  static const String mdnsServiceQuery = '_peerchat._tcp.local';
}
