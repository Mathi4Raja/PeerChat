String formatFileSizeBy1024(int bytes) {
  const double kb = 1024;
  const double mb = 1024 * 1024;
  const double gb = 1024 * 1024 * 1024;

  if (bytes < mb) {
    return '${(bytes / kb).toStringAsFixed(2)} KB';
  }
  if (bytes < gb) {
    return '${(bytes / mb).toStringAsFixed(2)} MB';
  }
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}
