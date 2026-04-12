import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:peerchat_secure/src/services/battery_status_service.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../services/app_icon_service.dart';

class WebShareAssetPicker extends StatefulWidget {
  final bool allowMultiple;
  final String title;
  final String confirmLabel;

  const WebShareAssetPicker({
    super.key,
    this.allowMultiple = true,
    this.title = 'Select Files',
    this.confirmLabel = 'Add Files',
  });

  @override
  State<WebShareAssetPicker> createState() => _WebShareAssetPickerState();
}

class _WebShareAssetPickerState extends State<WebShareAssetPicker>
    with SingleTickerProviderStateMixin {
  static const List<String> _documentExtensions = [
    '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.txt', '.rtf', '.csv', '.json', '.xml', '.zip', '.rar', '.7z',
  ];
  static const List<String> _audioExtensions = [
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus',
  ];
  static const List<String> _apkExtensions = ['.apk', '.xapk', '.apks'];

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final List<PlatformFile> _selectedFiles = [];

  List<Map<String, dynamic>> _apps = [];
  List<MediaAsset> _recentMedia = [];
  List<FileSystemEntity> _storageFiles = [];
  List<PlatformFile> _downloadFiles = [];
  List<PlatformFile> _documentFiles = [];
  List<PlatformFile> _audioFiles = [];
  List<PlatformFile> _apkFiles = [];
  List<PlatformFile> _largeFiles = [];

  String _currentPath = '/storage/emulated/0';
  String _searchQuery = '';
  bool _hasStoragePermission = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _initScanner();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initScanner() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);

    _hasStoragePermission =
        await appState.deviceService.checkAllFilesPermission();
    if (!_hasStoragePermission) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    _apps = await appState.deviceService.getInstalledApps();
    await _scanMedia();
    await _scanStorage(_currentPath);
    await _indexSmartCollections();

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _requestPermission() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final opened = await appState.deviceService.openAllFilesPermission();
    if (!opened) return;
    await Future.delayed(const Duration(seconds: 1));
    await _initScanner();
  }

  Future<void> _scanMedia() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final images = await appState.deviceService.getMediaAssets('image');
      final videos = await appState.deviceService.getMediaAssets('video');
      _recentMedia = [...images, ...videos];
    } catch (e) {
      debugPrint('Error scanning media: $e');
    }
  }

  Future<void> _scanStorage(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;

      final list = await dir.list(followLinks: false).toList();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _storageFiles = list;
        _currentPath = path;
      });
    } catch (e) {
      debugPrint('Error scanning storage: $e');
    }
  }

  Future<void> _indexSmartCollections() async {
    final roots = <Directory>[
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Documents'),
      Directory('/storage/emulated/0/Music'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/Pictures'),
      Directory('/storage/emulated/0/Movies'),
      Directory('/storage/emulated/0/Android/media'),
    ];

    final downloads = <PlatformFile>[];
    final docs = <PlatformFile>[];
    final audio = <PlatformFile>[];
    final apks = <PlatformFile>[];
    final large = <PlatformFile>[];

    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final file in _walkFiles(root, maxResults: 150)) {
        final entry = _toPlatformFile(file);
        if (entry == null) continue;
        final ext = p.extension(entry.name).toLowerCase();
        final lowerPath = entry.path?.toLowerCase() ?? '';

        if (lowerPath.contains('/download/')) downloads.add(entry);
        if (_documentExtensions.contains(ext)) docs.add(entry);
        if (_audioExtensions.contains(ext)) audio.add(entry);
        if (_apkExtensions.contains(ext)) apks.add(entry);
        if (entry.size >= 100 * 1024 * 1024) large.add(entry);
      }
    }

    _downloadFiles = _dedupeFiles(downloads).take(100).toList();
    _documentFiles = _dedupeFiles(docs).take(150).toList();
    _audioFiles = _dedupeFiles(audio).take(150).toList();
    _apkFiles = _dedupeFiles(apks).take(100).toList();
    _largeFiles = _dedupeFiles(large).take(50).toList();
  }

  Stream<File> _walkFiles(Directory root, {required int maxResults}) async* {
    var yielded = 0;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        yield entity;
        yielded++;
        if (yielded >= maxResults) break;
      }
    } catch (_) {}
  }

  PlatformFile? _toPlatformFile(File file) {
    try {
      final stat = file.statSync();
      return PlatformFile(
        path: file.path,
        name: p.basename(file.path),
        size: stat.size,
      );
    } catch (_) {
      return null;
    }
  }

  List<PlatformFile> _dedupeFiles(List<PlatformFile> files) {
    final seen = <String>{};
    final deduped = <PlatformFile>[];
    for (final file in files) {
      if (seen.add(file.path ?? file.name)) deduped.add(file);
    }
    return deduped;
  }

  void _toggleSelection(PlatformFile file) {
    setState(() {
      final index = _selectedFiles.indexWhere((f) => f.path == file.path);
      if (index >= 0) {
        _selectedFiles.removeAt(index);
        return;
      }
      if (!widget.allowMultiple) _selectedFiles.clear();
      _selectedFiles.add(file);
    });
  }

  bool _isItemSelected(String? path) => path != null && _selectedFiles.any((f) => f.path == path);

  void _confirmSelection() => Navigator.of(context).pop(_selectedFiles);

  List<PlatformFile> _filterFiles(List<PlatformFile> files) {
    if (_searchQuery.isEmpty) return files;
    return files.where((f) => '${f.name} ${f.path ?? ''}'.toLowerCase().contains(_searchQuery)).toList();
  }

  List<Map<String, dynamic>> _filterApps(List<Map<String, dynamic>> apps) {
    if (_searchQuery.isEmpty) return apps;
    return apps.where((a) => '${a['name']} ${a['packageName']}'.toLowerCase().contains(_searchQuery)).toList();
  }

  List<MediaAsset> _filterMedia(List<MediaAsset> assets) {
    if (_searchQuery.isEmpty) return assets;
    return assets.where((a) => '${a.name} ${a.path}'.toLowerCase().contains(_searchQuery)).toList();
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  IconData _iconForFile(String name) {
    final ext = p.extension(name).toLowerCase();
    if (_documentExtensions.contains(ext)) return Icons.description_rounded;
    if (_audioExtensions.contains(ext)) return Icons.music_note_rounded;
    if (_apkExtensions.contains(ext)) return Icons.android_rounded;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) return Icons.image_rounded;
    if (['.mp4', '.mov', '.mkv'].contains(ext)) return Icons.movie_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Smart', icon: Icon(Icons.auto_awesome_rounded)),
            Tab(text: 'Apps', icon: Icon(Icons.apps_rounded)),
            Tab(text: 'Media', icon: Icon(Icons.perm_media_rounded)),
            Tab(text: 'Files', icon: Icon(Icons.folder_rounded)),
          ],
        ),
      ),
      body: _isLoading
          ? _buildSkeletonUI()
          : !_hasStoragePermission
              ? _buildPermissionOverlay()
              : Column(
                  children: [
                    _buildSearchBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSmartTab(),
                          _buildAppsTab(),
                          _buildMediaTab(),
                          _buildFilesTab(),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _selectedFiles.isEmpty ? null : _buildSelectionBar(),
    );
  }

  Widget _buildSkeletonUI() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 10,
            itemBuilder: (context, index) => _buildSkeletonTile(index),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonTile(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 140, height: 14, decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(width: 200, height: 10, decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      color: AppTheme.bgCard,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search files, apps, media',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty ? null : IconButton(onPressed: _searchController.clear, icon: const Icon(Icons.close_rounded)),
          filled: true,
          fillColor: AppTheme.bgSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(color: AppTheme.bgCard, border: Border(top: BorderSide(color: AppTheme.primary, width: 0.5))),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(child: Text('${_selectedFiles.length} item(s) selected', style: const TextStyle(fontWeight: FontWeight.bold))),
            ElevatedButton(
              onPressed: _confirmSelection,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartTab() {
    final sections = [
      ('Downloads', _filterFiles(_downloadFiles), Icons.download_rounded),
      ('Documents', _filterFiles(_documentFiles), Icons.description_rounded),
      ('Audio', _filterFiles(_audioFiles), Icons.music_note_rounded),
      ('APK', _filterFiles(_apkFiles), Icons.android_rounded),
      ('Large Files', _filterFiles(_largeFiles), Icons.data_object_rounded),
    ];

    if (!sections.any((s) => s.$2.isNotEmpty)) return _buildEmptyState(Icons.auto_awesome_rounded, 'No results');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sections.where((s) => s.$2.isNotEmpty).map((s) => _buildSmartSection(title: s.$1, files: s.$2, icon: s.$3)).toList(),
    );
  }

  Widget _buildSmartSection({required String title, required List<PlatformFile> files, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: AppTheme.bgSurface.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: AppTheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${files.length} items'),
          ),
          ...files.take(5).map(_buildFileTile),
        ],
      ),
    );
  }

  Widget _buildAppsTab() {
    final apps = _filterApps(_apps);
    if (apps.isEmpty) return _buildEmptyState(Icons.apps_rounded, 'No apps');

    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        final file = PlatformFile(path: app['apkPath'], name: '${app['name']}.apk', size: app['size']);
        return _AppTile(
          name: app['name'],
          packageName: app['packageName'],
          sizeLabel: _formatSize(app['size']),
          selected: _isItemSelected(app['apkPath']),
          onTap: () => _toggleSelection(file),
          index: index,
        );
      },
    );
  }

  Widget _buildMediaTab() {
    final media = _filterMedia(_recentMedia);
    if (media.isEmpty) return _buildEmptyState(Icons.perm_media_rounded, 'No media');

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: media.length,
      itemBuilder: (context, index) {
        final asset = media[index];
        final file = PlatformFile(path: asset.path, name: asset.name, size: asset.size);
        final selected = _isItemSelected(asset.path);

        return GestureDetector(
          onTap: () => _toggleSelection(file),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: asset.mimeType.startsWith('video/')
                    ? Container(color: Colors.black26, child: const Icon(Icons.movie_rounded, color: Colors.white, size: 30))
                    : Image.file(File(asset.path), fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => Container(color: AppTheme.bgCard)),
              ),
              if (selected) Container(decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.4), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.check_circle, color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilesTab() {
    final visibleFiles = _searchQuery.isEmpty
        ? _storageFiles
        : _storageFiles.where((entity) {
            return p.basename(entity.path).toLowerCase().contains(_searchQuery);
          }).toList();

    return Column(
      children: [
        _buildPathBreadcrumb(),
        Expanded(
          child: ListView.builder(
            itemCount: visibleFiles.length,
            itemBuilder: (context, index) {
              final entity = visibleFiles[index];
              final name = p.basename(entity.path);
              if (entity is Directory) {
                return _buildSelectableTile(selected: false, icon: Icons.folder_rounded, title: name, subtitle: entity.path, onTap: () => _scanStorage(entity.path), trailing: const Icon(Icons.chevron_right));
              }
              final size = _safeFileLength(entity as File);
              return _buildSelectableTile(selected: _isItemSelected(entity.path), icon: _iconForFile(name), title: name, subtitle: _formatSize(size), onTap: () => _toggleSelection(PlatformFile(path: entity.path, name: name, size: size)));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPathBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.bgSurface,
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 18, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(_currentPath, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis)),
          if (_currentPath != '/storage/emulated/0')
            IconButton(icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: () => _scanStorage(p.dirname(_currentPath))),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: Colors.grey), const SizedBox(height: 16), Text(message, style: const TextStyle(color: Colors.grey))]));
  }

  Widget _buildSelectableTile({required bool selected, required IconData icon, required String title, required String subtitle, required VoidCallback onTap, Widget? trailing}) {
    return ListTile(
      onTap: onTap,
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: selected ? AppTheme.primary.withOpacity(0.1) : AppTheme.bgSurface, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: selected ? AppTheme.primary : AppTheme.accent)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? Checkbox(value: selected, onChanged: (_) => onTap(), activeColor: AppTheme.primary),
    );
  }

  Widget _buildFileTile(PlatformFile file) => _buildSelectableTile(selected: _isItemSelected(file.path), icon: _iconForFile(file.name), title: file.name, subtitle: _formatSize(file.size), onTap: () => _toggleSelection(file));

  Widget _buildPermissionOverlay() {
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.security_rounded, size: 64, color: AppTheme.primary),
      const SizedBox(height: 20),
      const Text('Access Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      const Text('PeerChat needs All Files Access to scan for shareable assets.', textAlign: TextAlign.center),
      const SizedBox(height: 30),
      ElevatedButton(onPressed: _requestPermission, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)), child: const Text('Grant Access', style: TextStyle(color: Colors.white))),
    ])));
  }

  int _safeFileLength(File file) { try { return file.lengthSync(); } catch (_) { return 0; } }
}

/// Expert-grade App Tile with lazy icon loading and staggered entry animation.
class _AppTile extends StatefulWidget {
  final String name;
  final String packageName;
  final String sizeLabel;
  final bool selected;
  final VoidCallback onTap;
  final int index;

  const _AppTile({
    required this.name,
    required this.packageName,
    required this.sizeLabel,
    required this.selected,
    required this.onTap,
    required this.index,
  });

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    
    Future.delayed(Duration(milliseconds: 50 * widget.index.clamp(0, 10)), () {
      if (mounted) _animController.forward();
    });

    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.appIconService.getIcon(widget.packageName) == null) {
      appState.appIconService.loadIcon(widget.packageName, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final iconBytes = appState.appIconService.getIcon(widget.packageName);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ListTile(
          onTap: widget.onTap,
          leading: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: iconBytes != null
                  ? Image.memory(iconBytes, fit: BoxFit.cover)
                  : const Icon(Icons.android_rounded, color: AppTheme.accent),
            ),
          ),
          title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${widget.sizeLabel} • ${widget.packageName}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Checkbox(value: widget.selected, onChanged: (_) => widget.onTap(), activeColor: AppTheme.primary),
        ),
      ),
    );
  }
}
