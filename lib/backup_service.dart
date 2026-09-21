import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ComparaBackupBridge {
  static const _channel =
      MethodChannel('com.angel.comparaprecios.compara_precios/backups');

  static Future<Map<String, dynamic>> write({
    required String fileName,
    required String content,
    bool overwrite = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writeBackup',
      {
        'fileName': fileName,
        'content': content,
        'overwrite': overwrite,
      },
    );
    return Map<String, dynamic>.from(raw ?? const {});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listBackups');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<String> read(String uri) async {
    return await _channel.invokeMethod<String>(
          'readBackup',
          {'uri': uri},
        ) ??
        '';
  }
}

class ComparaBackupService {
  static const _autoKey = 'compara_auto_backup_enabled';
  static const _lastKey = 'compara_last_auto_backup_at';

  static bool _sensitive(String key) {
    final k = key.toLowerCase();
    return k.contains('apikey') ||
        k.contains('api_key') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('token');
  }

  static Future<Map<String, dynamic>> _payload() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    final excluded = <String>[];
    for (final key in prefs.getKeys()) {
      if (_sensitive(key)) {
        excluded.add(key);
        continue;
      }
      final value = prefs.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        values[key] = value;
      }
    }
    return {
      'format': 'ComparaPreciosBackup',
      'formatVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'preferences': values,
      'excludedSensitivePreferences': excluded,
    };
  }

  static Future<Map<String, dynamic>> createManual() async {
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return ComparaBackupBridge.write(
      fileName:
          'Compara-Precios-Backup-${now.year}${p(now.month)}${p(now.day)}-'
          '${p(now.hour)}${p(now.minute)}${p(now.second)}.json',
      content: jsonEncode(await _payload()),
    );
  }

  static Future<void> autoBackupIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_autoKey) ?? true)) return;
    final last = DateTime.tryParse(prefs.getString(_lastKey) ?? '');
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return;
    }
    await ComparaBackupBridge.write(
      fileName: 'Compara-Precios-AutoBackup.json',
      content: jsonEncode(await _payload()),
      overwrite: true,
    );
    await prefs.setString(_lastKey, now.toIso8601String());
  }

  static Future<bool> autoEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_autoKey) ?? true;
  }

  static Future<void> setAutoEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_autoKey, enabled);
  }

  static Future<void> restore(String uri) async {
    final raw = await ComparaBackupBridge.read(uri);
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != 'ComparaPreciosBackup' ||
        decoded['preferences'] is! Map) {
      throw Exception('No es una copia válida de Compara Precios.');
    }
    final data = decoded['preferences'] as Map;
    final prefs = await SharedPreferences.getInstance();

    // Keep the API key currently configured on this phone: backups never
    // contain it and restore must not erase it.
    final currentApiKey = prefs.getString('apiKey');
    final auto = prefs.getBool(_autoKey) ?? true;
    await prefs.clear();

    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (_sensitive(key)) continue;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List) {
        await prefs.setStringList(
          key,
          value.map((e) => e.toString()).toList(),
        );
      }
    }
    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      await prefs.setString('apiKey', currentApiKey);
    }
    if (!prefs.containsKey(_autoKey)) {
      await prefs.setBool(_autoKey, auto);
    }
  }
}

class ComparaBackupPage extends StatefulWidget {
  const ComparaBackupPage({super.key});

  @override
  State<ComparaBackupPage> createState() => _ComparaBackupPageState();
}

class _ComparaBackupPageState extends State<ComparaBackupPage> {
  bool loading = true;
  bool working = false;
  bool autoEnabled = true;
  List<Map<String, dynamic>> backups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await ComparaBackupService.autoEnabled();
    final data = await ComparaBackupBridge.list();
    if (!mounted) return;
    setState(() {
      autoEnabled = enabled;
      backups = data;
      loading = false;
    });
  }

  Future<void> _create() async {
    setState(() => working = true);
    try {
      await ComparaBackupService.createManual();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copia guardada en Descargas/ComparaPrecios.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude crear la copia: $e')),
      );
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Restaurar copia'),
            content: Text(
              'Se restaurarán ZIP code, tiendas y preferencias desde '
              '"${item['name'] ?? 'backup'}". La clave API actual no se modifica.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Restaurar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => working = true);
    try {
      await ComparaBackupService.restore(item['uri']?.toString() ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copia restaurada. Vuelve a abrir la pantalla principal.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude restaurar: $e')),
      );
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Copias de seguridad')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Copia automática diaria'),
                    subtitle: const Text(
                      'Se guarda fuera de la app en Descargas/ComparaPrecios.',
                    ),
                    value: autoEnabled,
                    onChanged: working
                        ? null
                        : (v) async {
                            await ComparaBackupService.setAutoEnabled(v);
                            if (mounted) setState(() => autoEnabled = v);
                          },
                  ),
                  FilledButton.icon(
                    onPressed: working ? null : _create,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Crear copia ahora'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'La clave de SerpApi no se incluye en las copias.',
                  ),
                  const Divider(height: 28),
                  if (backups.isEmpty)
                    const Text('Todavía no hay copias guardadas.'),
                  for (final item in backups)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: Text(item['name']?.toString() ?? 'Backup'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: working ? null : () => _restore(item),
                      ),
                    ),
                ],
              ),
      );
}
