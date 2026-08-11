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

String _localDigits(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  return d.startsWith('0') ? d.substring(1) : d;
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
      final matchUsers =
          matches.map((m) => (m as Map).cast<String, dynamic>()).toList();
      for (final c in contacts) {
        final can = _localDigits(c.phone);
        if (can.length < 6) continue;
        for (final u in matchUsers) {
          final uLocal = _localDigits(u['phone'] as String? ?? '');
          final shorter = can.length <= uLocal.length ? can : uLocal;
          final longer = can.length <= uLocal.length ? uLocal : can;
          if (shorter.length >= 6 && longer.endsWith(shorter)) {
            c.matchedUser = u;
            break;
          }
        }
      }
    } catch (_) {}

    contacts.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return contacts;
  }
}