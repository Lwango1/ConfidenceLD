import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/contacts_service.dart';
import '../services/api_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<PhoneContact> _contacts = [];
  bool _loading = true;
  bool _permissionDenied = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    final list = await ContactsService.getContactsWithMatches();
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _loading = false;
    });
  }

  List<PhoneContact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.displayName.toLowerCase().contains(q) || c.phone.contains(q);
    }).toList();
  }

  Future<void> _invite(PhoneContact contact) async {
    final phone = contact.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent('Installe ConfidenceLD pour discuter en toute confidentialité. Télécharge l\'app ici : https://github.com/Lwango1/ConfidenceLD/releases/latest')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openChat(Map<String, dynamic> user) {
    Navigator.of(context).pop();
    Navigator.pushNamed(context, '/chat', arguments: {
      'type': 'direct',
      'userId': user['id'],
      'displayName': user['displayName'],
      'avatar': user['avatar'],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.contacts_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Autorisez l\'accès aux contacts pour continuer'),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Autoriser')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un contact...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _query = ''),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? const Center(child: Text('Aucun contact trouvé'))
                          : ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final c = _filtered[i];
                                final user = c.matchedUser;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: user?['avatar'] != null
                                        ? NetworkImage('${ApiConfig.baseUrl}${user!['avatar']}')
                                        : null,
                                    child: user?['avatar'] != null
                                        ? null
                                        : Text(
                                            c.displayName.substring(0, 1).toUpperCase(),
                                          ),
                                  ),
                                  title: Text(
                                    c.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    user != null
                                        ? '${user['displayName']} est sur ConfidenceLD'
                                        : c.phone,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: user != null
                                      ? const Icon(Icons.chat_bubble_outline)
                                      : TextButton(
                                          onPressed: () => _invite(c),
                                          child: const Text('Inviter'),
                                        ),
                                  onTap: user != null ? () => _openChat(user) : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}