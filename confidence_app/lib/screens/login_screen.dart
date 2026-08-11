import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _avatarPath;
  bool _registerMode = false;
  bool _loading = false;
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _registerMode ? _pickAvatar : null,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: _avatarPath != null
                        ? ClipOval(
                            child: Image.file(
                              File(_avatarPath!),
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.visibility_off_outlined,
                            color: Colors.white, size: 44),
                  ),
                ),
                if (_registerMode)
                  TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.photo_camera_outlined,
                        color: Colors.white70, size: 18),
                    label: Text(
                      _avatarPath != null ? 'Changer la photo' : 'Ajouter une photo de profil',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'ConfidenceLD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Messages et médias en vue unique. Vos secrets restent secrets.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (_registerMode) ...[
                  TextField(
                    controller: _displayCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _input('Votre nom affiché'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: _input('Numéro de téléphone (optionnel, sans indicatif)'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _usernameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Username (pseudo)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Mot de passe'),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)
                        : Text(_registerMode ? 'Créer mon compte' : 'Se connecter',
                            style: const TextStyle(fontSize: 16)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _registerMode = !_registerMode;
                    _error = '';
                  }),
                  child: Text(
                    _registerMode
                        ? 'J\'ai déjà un compte'
                        : 'Je n\'ai pas de compte, je m\'inscris',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (file == null) return;
    setState(() => _avatarPath = file.path);
  }

  InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (username.isEmpty || password.length < 6) {
        throw Exception('Mot de passe : 6 caractères minimum');
      }
      Map<String, dynamic> data;
      if (_registerMode) {
        final display = _displayCtrl.text.trim();
        final phone = _phoneCtrl.text.trim();
        if (display.isEmpty) throw Exception('Entrez votre nom affiché');
        data = await ApiService.register(
          username: username,
          password: password,
          displayName: display,
          phone: phone,
        );
      } else {
        data = await ApiService.login(username: username, password: password);
      }
      final user = data['user'] as Map<String, dynamic>;
      final token = data['token'] as String;
      ApiService.token = token;
      ApiService.userId = user['id'] as int;
      ApiService.username = user['username'] as String;
      ApiService.displayName = user['displayName'] as String? ?? username;
      await Session.save(
        token: token,
        userId: user['id'] as int,
        username: user['username'] as String,
        displayName: user['displayName'] as String? ?? username,
      );
      if (_avatarPath != null && _registerMode) {
        try {
          await ApiService.uploadAvatar(_avatarPath!);
        } catch (_) {}
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _displayCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }
}