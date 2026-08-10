import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'api_service.dart';

class PhoneContact {
  final String displayName;
  final String phone;
  Map<String, dynamic>? matchedUser;

  PhoneContact({
    required this.displayName,
    required this.phone,
    this.matchedUser,
  });
}

class ContactsService {
  static Future<bool> ensurePermission() async {
    final granted = await ph.Permission.contacts.request().isGranted;
    return granted;
  }

  static Future<List<PhoneContact>> getContactsWithMatches() async {
    final allowed = await ensurePermission();
    if (!allowed) return [];

    final raw = await FlutterContacts.getAll(
      properties: ContactProperties.all,
    );

    final seen = <String>{};
    final contacts = <PhoneContact>[];
    for (final c in raw) {
      final name = c.displayName?.trim().isNotEmpty == true
          ? c.displayName!.trim()
          : 'Inconnu';
      for (final p in c.phones) {
        final rawPhone = p.number.trim();
        if (rawPhone.isEmpty || seen.contains(rawPhone)) continue;
        seen.add(rawPhone);
        contacts.add(PhoneContact(
          displayName: name,
          phone: rawPhone,
        ));
      }
    }

    final phones = contacts.map((c) => c.phone).toList();
    try {
      final matching = await ApiService.matchContacts(phones);
      final matches = matching['matches'] as List<dynamic>? ?? [];
      final userByPhone = <String, Map<String, dynamic>>{};
      for (final m in matches) {
        final map = (m as Map).cast<String, dynamic>();
        final phone = (map['phone'] as String? ?? '').replaceAll('+', '');
        userByPhone[phone] = map;
      }
      for (final c in contacts) {
        final stripped = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
        final match = userByPhone[stripped];
        if (match != null) {
          c.matchedUser = match;
        }
      }
    } catch (_) {}

    contacts.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return contacts;
  }
}