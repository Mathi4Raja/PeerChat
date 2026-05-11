class AppVersion {
  /// The current version of the application.
  /// 
  /// This should be kept in sync with the version in pubspec.yaml.
  static const String version = '1.1.0';

  /// The build name/codename for this release.
  static const String codename = 'Secure Mesh';

  /// Returns the formatted version string for display.
  static String get displayVersion => 'Version $version ($codename)';
}
