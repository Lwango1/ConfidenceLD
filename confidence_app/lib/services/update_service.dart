import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class UpdateInfo {
  final String version;
  final String? apkUrl;
  final String releaseNotes;

  UpdateInfo({required this.version, this.apkUrl, this.releaseNotes = ''});

  bool get hasUpdate => apkUrl != null;
}

class UpdateService {
  static ValueNotifier<double> downloadNotifier = ValueNotifier(0.0);
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/version'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return UpdateInfo(
        version: data['version'] as String? ?? '',
        apkUrl: data['apkUrl'] as String?,
        releaseNotes: data['releaseNotes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static bool isNewer(String serverVersion, String currentVersion) {
    final s = _parse(serverVersion);
    final c = _parse(currentVersion);
    if (s.length != c.length) return true;
    for (int i = 0; i < s.length; i++) {
      if (s[i] > c[i]) return true;
      if (s[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final cleaned = v.replaceAll(RegExp('[^0-9.]'), '');
    return cleaned.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle version disponible'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} disponible'),
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(info.releaseNotes, style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 12),
              const Text(
                'Mettez à jour pour profiter des dernières améliorations. Vos messages et conversations restent confidentiels.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadAndInstall(context, info.apkUrl!);
            },
            child: const Text('Mettre à jour'),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url) async {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DownloadDialog(),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ConfidenceLD-update.apk');
      final request = http.Request('GET', Uri.parse(url));
      final streamed = await request.send();
      final total = streamed.contentLength ?? 0;
      var downloaded = 0;
      final raf = await file.open(mode: FileMode.write);
      await for (final chunk in streamed.stream) {
        await raf.writeFrom(chunk);
        downloaded += chunk.length;
        final progress = total > 0 ? downloaded / total : 0.0;
        downloadNotifier.value = progress;
      }
      
      await raf.close();
      downloadNotifier.value = 1.0;

      if (context.mounted) {
        Navigator.of(context).pop(_DownloadDialog);
      }

      final result = await OpenFilex.open(file.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.type == ResultType.done
                  ? 'APK téléchargé. Confirmez l\'installation dans la fenêtre qui s\'ouvre.'
                  : 'Téléchargement terminé. Ouvrez l\'APK depuis vos fichiers pour installer.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de mise à jour : $e')),
        );
      }
    }
  }

    // notifier public: downloadNotifier
}

class _DownloadDialog extends StatelessWidget {
  const _DownloadDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mise à jour'),
      content: ValueListenableBuilder<double>(
        valueListenable: UpdateService.downloadNotifier,
        builder: (ctx, progress, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            const SizedBox(height: 10),
            Text('${(progress * 100).toStringAsFixed(0)} %'),
            const SizedBox(height: 6),
            const Text('Téléchargement en cours...',
                style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}