import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> otherUser;
  const ChatScreen({super.key, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  late final SocketService _socket;
  final List<Message> _messages = [];
  bool _viewOnce = false;

  int get _otherId => widget.otherUser['id'] as int? ?? 0;
  int? get _conversationId => widget.otherUser['conversationId'] as int?;

  @override
  void initState() {
    super.initState();
    _socket = SocketService(
      onMessage: _handleIncoming,
      onMessageRead: (_) {},
      onMediaDestroyed: (_) {},
    );
    _socket.connect();
    final cid = _conversationId;
    if (cid != null) {
      _socket.markConversationRead(cid);
    }
    loadHistory();
  }

  Future<void> loadHistory() async {
    final cid = _conversationId;
    if (cid == null) return;
    try {
      final res = await ApiService.getMessages(cid);
      if (!mounted) return;
      final data = res['messages'] as List<dynamic>? ?? [];
      setState(() {
        _messages.clear();
        _messages.addAll(data.map((m) => Message.fromJson((m as Map).cast<String, dynamic>())));
      });
    } catch (_) {}
  }

  void _handleIncoming(Message msg) {
    if (_conversationId != null &&
        msg.conversationId == _conversationId &&
        msg.senderId != (ApiService.userId ?? 0)) {
      if (!mounted) return;
      setState(() => _messages.add(msg));
    } else if (_conversationId == null && msg.senderId == _otherId) {
      if (!mounted) return;
      setState(() => _messages.add(msg));
    }
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _messages.add(Message(
          id: DateTime.now().millisecondsSinceEpoch,
          conversationId: 0,
          senderId: ApiService.userId ?? 0,
          type: 'text',
          content: text,
          viewOnce: _viewOnce,
        )));
    _textCtrl.clear();
    final cid = _conversationId;
    _socket.sendMessage(
      conversationId: cid,
      toUserId: cid == null ? _otherId : null,
      type: 'text',
      content: text,
      viewOnce: _viewOnce,
    );
  }

  Future<void> _sendMedia() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    try {
      final uploaded = await ApiService.uploadMedia(
        filePath: file.path,
        mimeType: 'image/jpeg',
      );
      final mediaId = uploaded['mediaId'] as int;
      if (!mounted) return;
      setState(() => _messages.add(Message(
            id: DateTime.now().millisecondsSinceEpoch,
            conversationId: 0,
            senderId: ApiService.userId ?? 0,
            type: 'media',
            mediaId: mediaId,
            mediaUrl: (uploaded['url'] as String?),
            viewOnce: _viewOnce,
          )));
      _socket.sendMessage(
        conversationId: _conversationId,
        toUserId: _conversationId == null ? _otherId : null,
        type: 'media',
        mediaId: mediaId,
        viewOnce: _viewOnce,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  void _showMedia(Message msg) {
    final url = msg.mediaUrl;
    if (url == null) {
      return;
    }
    if (!msg.viewOnce) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: Image.network(
            url,
            errorBuilder: (ctx, err, stack) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Média indisponible'),
            ),
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: Stack(
          children: [
            Image.network(url),
            Positioned(
              top: 8,
              right: 8,
              child: FilledButton.icon(
                onPressed: () {
                  _socket.confirmMedia(mediaId: msg.mediaId!, ownerId: _otherId);
                  Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.visibility_off, size: 18),
                label: const Text('Vue unique - fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: (widget.otherUser['avatar'] as String?) != null
                  ? NetworkImage('${ApiConfig.baseUrl}${widget.otherUser['avatar']}')
                  : null,
              child: (widget.otherUser['avatar'] as String?) != null
                  ? null
                  : Text(
                      (widget.otherUser['displayName'] as String? ?? '?')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUser['displayName'] as String? ?? '',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.otherUser['type'] == 'group')
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.group, size: 18),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Envoyez votre premier message confidentiel'))
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[_messages.length - 1 - i];
                      return _MessageBubble(
                        message: msg,
                        isMine: msg.senderId == (ApiService.userId ?? 0),
                        onTap: msg.type == 'media' ? () => _showMedia(msg) : null,
                      );
                    },
                  ),
          ),
          if (_viewOnce)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.amber.shade100,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mode vue unique activé : le message sera détruit après lecture',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    tooltip: 'Envoyer une photo',
                    onPressed: _sendMedia,
                  ),
                  IconButton(
                    icon: Icon(
                      _viewOnce ? Icons.visibility_off : Icons.visibility_outlined,
                      color: _viewOnce ? Colors.amber : Colors.grey,
                    ),
                    tooltip: 'Vue unique',
                    onPressed: () => setState(() => _viewOnce = !_viewOnce),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      decoration: InputDecoration(
                        hintText: 'Message confidentiel...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _socket.dispose();
    _textCtrl.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final VoidCallback? onTap;

  const _MessageBubble({required this.message, required this.isMine, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isMine ? const Color(0xFF219536) : Colors.grey.shade300;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: message.type == 'media' ? _mediaContent() : _textContent(),
          ),
          if (message.status == 'sent' && isMine)
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 4),
              child: Icon(Icons.done, size: 14, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _textContent() => Text(
        message.content ?? '',
        style: TextStyle(color: isMine ? Colors.white : Colors.black87, fontSize: 15),
      );

  Widget _mediaContent() {
    final url = message.mediaUrl;
    if (url == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined),
            SizedBox(width: 8),
            Text('Photo'),
          ],
        ),
      );
    }
    final size = BoxConstraints(maxWidth: 200, maxHeight: 140);
    if (!message.viewOnce) {
      return InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, width: 200, height: 140, fit: BoxFit.cover),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: size,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, width: 200, height: 140, fit: BoxFit.cover),
            ),
            Container(
              width: 200,
              height: 140,
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.visibility_off, color: Colors.white, size: 32),
                  const SizedBox(height: 6),
                  const Text('Vue unique', style: TextStyle(color: Colors.white)),
                  Text('Touchez pour voir',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}