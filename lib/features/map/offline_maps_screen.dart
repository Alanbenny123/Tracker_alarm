import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/offline_packs_provider.dart';
import '../../services/offline_pack_store.dart';

class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  final link = TextEditingController();
  final regionSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(offlinePacksProvider).refreshCatalog();
    });
  }

  @override
  void dispose() {
    link.dispose();
    regionSearch.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final uri = Uri.tryParse(link.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an HTTPS offline pack link.')),
      );
      return;
    }
    await _install(uri);
  }

  Future<void> _install(Uri uri) async {
    try {
      await ref.read(offlinePacksProvider).download(uri);
      if (!mounted) return;
      link.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Offline map installed.')));
    } catch (_) {
      // The controller shows the specific download/validation error.
    }
  }

  Future<void> _delete(OfflinePack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${pack.name}?'),
        content: const Text(
          'Offline map and searchable places will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(offlinePacksProvider).delete(pack);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(offlinePacksProvider);
    final query = regionSearch.text.trim().toLowerCase();
    bool matchesRegion(String name, String id) =>
        query.isEmpty ||
        name.toLowerCase().contains(query) ||
        id.replaceAll('-', ' ').toLowerCase().contains(query);
    final installed = controller.packs
        .where((pack) => matchesRegion(pack.name, pack.id))
        .toList();
    final available = controller.catalog
        .where((listing) => matchesRegion(listing.name, listing.id))
        .toList();
    final progress = controller.totalBytes == null || controller.totalBytes == 0
        ? null
        : (controller.receivedBytes / controller.totalBytes!).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Download a prepared OpenStreetMap pack while online. You can keep several regions on your phone. A pack includes map tiles and searchable places; GPS alarms use no map connection after a destination is set.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: regionSearch,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search states or regions',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear region search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        regionSearch.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Installed regions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (controller.packs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No offline regions installed yet.'),
            ),
          if (controller.packs.isNotEmpty && installed.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No installed regions match your search.'),
            ),
          for (final pack in installed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.offline_pin_outlined),
                title: Text(pack.name),
                subtitle: Text(
                  '${pack.placeCount} places · zoom ${pack.minZoom}–${pack.maxZoom}',
                ),
                trailing: IconButton(
                  tooltip: 'Delete ${pack.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(pack),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available regions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh region list',
                onPressed: controller.loadingCatalog
                    ? null
                    : controller.refreshCatalog,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (controller.loadingCatalog) const LinearProgressIndicator(),
          if (controller.catalogError case final message?)
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!controller.loadingCatalog &&
              controller.catalog.isEmpty &&
              controller.catalogError == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No regional packs have been published yet.'),
            ),
          if (!controller.loadingCatalog &&
              controller.catalog.isNotEmpty &&
              available.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No available regions match your search.'),
            ),
          for (final listing in available)
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(listing.name),
              subtitle: Text(
                controller.packs.any((pack) => pack.id == listing.id)
                    ? 'Installed · tap to update'
                    : 'Download for offline use',
              ),
              trailing: const Icon(Icons.download_outlined),
              onTap: controller.downloading
                  ? null
                  : () => _install(listing.url),
            ),
          const SizedBox(height: 24),
          Text(
            'Add from a link',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use a prepared regional pack link if it is not in the list above.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: link,
            enabled: !controller.downloading,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Pack link (HTTPS)',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: controller.downloading ? null : _download,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download pack'),
          ),
          if (controller.downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${(controller.receivedBytes / 1048576).toStringAsFixed(1)} MB downloaded',
            ),
          ],
          if (controller.error case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Map and place data © OpenStreetMap contributors · ODbL'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('OpenStreetMap licence'),
            ),
          ),
        ],
      ),
    );
  }
}
