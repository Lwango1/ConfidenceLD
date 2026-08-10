import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/update_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  int get _userId => ApiService.userId ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await UpdateService.checkForUpdate();
      if (info == null || !info.hasUpdate) return;
      final current = await UpdateService.getCurrentVersion();
      if (!UpdateService.isNewer(info.version, current)) return;
      if (!mounted) return;
      await UpdateService.showUpdateDialog(context, info);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final convos = await ApiService.getConversations();
      final users = await ApiService.getUsers();
      if (mounted) {
        setState(() {
          _conversations = (convos['conversations'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          _users = users.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _filter(String tab) {
    switch (tab) {
      case 'nonlues':
        return _conversations.where((c) => (c['unreadCount'] ?? 0) > 0).toList();
      case 'favoris':
        return _conversations.where((c) => c['isFavorite'] == true).toList();
      case 'groupes':
        return _conversations.where((c) => c['type'] == 'group').toList();
      default:
        return _conversations;
    }
  }

  void _openConversation(Map<String, dynamic> conv) {
    Navigator.pushNamed(context, '/chat', arguments: {
      'conversationId': conv['id'],
      'type': conv['type'],
      'displayName': conv['displayName'],
      'avatar': conv['avatar'],
      if (conv['userId'] != null) 'userId': conv['userId'],
    });
  }

  Future<void> _createGroup(BuildContext sheetCtx) async {
    final selected = <int>{};
    final mine = _users.where((u) => u['id'] != _userId).toList();
    final nameCtrl = TextEditingController();
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Nouveau groupe'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom du groupe'),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: mine.map((u) {
                      final id = u['id'] as int;
                      return CheckboxListTile(
                        dense: true,
                        title: Text(u['displayName'] as String? ?? ''),
                        value: selected.contains(id),
                        onChanged: (v) {
                          setDlg(() {
                            if (v == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty || selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un nom et au moins un membre')),
      );
      return;
    }
    try {
      await ApiService.createGroup(name: name, memberIds: selected.toList());
      if (!mounted) return;
      Navigator.pop(sheetCtx);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _buildConversationRow(Map<String, dynamic> conv) {
    final displayName = conv['displayName'] as String? ?? '';
    final avatar = conv['avatar'];
    final lastMsg = conv['lastMessage'] as Map<String, dynamic>?;
    final unread = (conv['unreadCount'] as int? ?? 0);
    final time = conv['lastMessageAt'] as String? ?? '';
    final subtitle = lastMsg != null
        ? (lastMsg['type'] == 'media' ? 'Photo' : lastMsg['content'] as String? ?? '')
        : 'Aucun message';
    return ListTile(
      leading: _Avatar(displayName: displayName, avatar: avatar),
      title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time.isNotEmpty)
            Text(
              _formatTime(time),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xFF25D366),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$unread',
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
        ],
      ),
      onTap: () => _openConversation(conv),
    );
  }

  static String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ConfidenceLD'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'refresh') await _load();
                if (v == 'group') await _createGroup(context);
                if (v == 'logout') {
                  await Session.clear();
                  if (!mounted) return;
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('Actualiser')),
                PopupMenuItem(value: 'group', child: Text('Nouveau groupe')),
                PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
              ],
            ),
            IconButton(
              onPressed: () async {
                await Navigator.pushNamed(context, '/contacts');
                if (mounted) await _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Tous'),
              Tab(text: 'Non lues'),
              Tab(text: 'Favoris'),
              Tab(text: 'Groupes'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Nouvelle discussion',
          onPressed: () async {
            await Navigator.pushNamed(context, '/contacts');
            if (mounted) await _load();
          },
          child: const Icon(Icons.chat_bubble_outline),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: const [
                  _FilterTab(key: ValueKey('tous'), tab: 'tous'),
                  _FilterTab(key: ValueKey('nonlues'), tab: 'nonlues'),
                  _FilterTab(key: ValueKey('favoris'), tab: 'favoris'),
                  _FilterTab(key: ValueKey('groupes'), tab: 'groupes'),
                ],
              ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String tab;
  const _FilterTab({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      // Parent state accessible via a static holder approach
      final home = ctx.findAncestorStateOfType<_HomeScreenState>();
      if (home == null) return const SizedBox.shrink();
      final items = home._filter(tab);
      if (items.isEmpty) {
        return const Center(
          child: Text(
            'Aucune conversation',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () => home._load().then((_) {}),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => Divider(height: 1, indent: 72),
          itemBuilder: (_, i) => home._buildConversationRow(items[i]),
        ),
      );
    });
  }
}

class _Avatar extends StatelessWidget {
  final Object? displayName;
  final Object? avatar;
  final double radius;
  const _Avatar({this.displayName, this.avatar, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final url = avatar as String?;
    final initial = (displayName as String? ?? '?').substring(0, 1).toUpperCase();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage('${ApiConfig.baseUrl}$url'),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      child: Text(initial, style: TextStyle(fontSize: radius * 0.8)),
    );
  }
}