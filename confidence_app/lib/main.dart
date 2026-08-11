import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/call_screens.dart';
import 'services/session.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await Session.restore();
  runApp(ConfidenceLDApp(startLoggedIn: loggedIn));
}

class ConfidenceLDApp extends StatelessWidget {
  final bool startLoggedIn;
  const ConfidenceLDApp({super.key, required this.startLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConfidenceLD',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C5364),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: startLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/contacts': (_) => const ContactsScreen(),
        '/chat': (_) => ChatScreen(otherUser: const {}),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(builder: (_) => ChatScreen(otherUser: args));
        }
        if (settings.name == '/call') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
              fullscreenDialog: true, builder: (_) => ActiveCallScreen(
                    callId: args['callId'] as String,
                    peerId: args['peerId'] as int,
                    displayName: args['displayName'] as String,
                    avatar: args['avatar'] as String?,
                    isVideo: args['isVideo'] == true,
                    initiatedByMe: args['initiatedByMe'] == true,
                  ));
        }
        return null;
      },
    );
  }
}