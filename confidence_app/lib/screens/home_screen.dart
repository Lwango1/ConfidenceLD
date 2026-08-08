import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Map<String, dynamic>> _users = [];
  final List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await ApiService.getUsers();
      if (mounted) {
        setState(() {
          _users
            ..clear()
            ..addAll(users.cast<Map<String, dynamic>>());
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ConfidenceLD'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') {
                await Session.clear();
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nouvelle conversation',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._users.map(_buildUser),
                const Divider(height: 32),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Mes conversations',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_conversations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune conversation. Choisissez un utilisateur pour commencer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._conversations.map(_buildConversation),
              ],
            ),
    );
  }

  Widget _buildUser(Map<String, dynamic> user) {
    return ListTile(
      leading: CircleAvatar(
        child: Text((user['displayName'] as String? ?? '?').substring(0, 1).toUpperCase()),
      ),
      title: Text(user['displayName'] as String? ?? user['username']),
      subtitle: Text('@${user['username']}'),
      trailing: const Icon(Icons.chat_bubble_outline),
      onTap: () => Navigator.pushNamed(context, '/chat', arguments: user),
    );
  }

  Widget _buildConversation(Map<String, dynamic> conv) {
    return ListTile(
      leading: CircleAvatar(
        child: Text((conv['displayName'] as String? ?? '?').substring(0, 1).toUpperCase()),
      ),
      title: Text(conv['displayName'] as String? ?? ''),
      subtitle: Text(conv['lastMessageAt']?.toString() ?? ''),
      onTap: () => Navigator.pushNamed(context, '/chat', arguments: {
        'id': conv['userId'],
        'username': conv['displayName'],
        'displayName': conv['displayName'],
      }),
    );
  }
}