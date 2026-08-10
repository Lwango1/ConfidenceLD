import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class Message {
  final int id;
  final int conversationId;
  final int senderId;
  final String type;
  final String? content;
  final int? mediaId;
  final String? mediaUrl;
  final bool viewOnce;
  final String status;
  final String createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = 'text',
    this.content,
    this.mediaId,
    this.mediaUrl,
    this.viewOnce = false,
    this.status = 'sent',
    this.createdAt = '',
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as int,
        conversationId: json['conversationId'] as int,
        senderId: json['senderId'] as int,
        type: json['type'] as String? ?? 'text',
        content: json['content'] as String?,
        mediaId: json['mediaId'] as int?,
        mediaUrl: json['mediaUrl'] as String?,
        viewOnce: json['viewOnce'] == true,
        status: json['status'] as String? ?? 'sent',
        createdAt: json['createdAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'type': type,
        'content': content,
        'mediaId': mediaId,
        'mediaUrl': mediaUrl,
        'viewOnce': viewOnce,
        'status': status,
        'createdAt': createdAt,
      };
}

class SocketService {
  final void Function(Message message) onMessage;
  final void Function(int messageId) onMessageRead;
  final void Function(int mediaId) onMediaDestroyed;
  final void Function(int conversationId, int unreadCount)? onUnreadChange;
  final void Function(int conversationId)? onConversationRead;
  final void Function(int conversationId, bool isFavorite)? onFavoriteChange;

  io.Socket? _socket;

  SocketService({
    required this.onMessage,
    required this.onMessageRead,
    required this.onMediaDestroyed,
    this.onUnreadChange,
    this.onConversationRead,
    this.onFavoriteChange,
  });

  void connect() {
    _socket?.dispose();
    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': ApiService.token})
          .build(),
    );
    _socket!.onConnect((_) => debugPrint('Socket connecté'));
    _socket!.on('message:new', (data) {
      final map = (data as Map).cast<String, dynamic>();
      if (map['mediaUrl'] is String) {
        map['mediaUrl'] = '${ApiConfig.baseUrl}$map[mediaUrl]';
      }
      onMessage(Message.fromJson(map));
    });
    _socket!.on('message:read', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onMessageRead(map['id'] as int);
    });
    _socket!.on('media:destroyed', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onMediaDestroyed(map['mediaId'] as int);
    });
    _socket!.on('conversation:unread', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onUnreadChange?.call(
        map['conversationId'] as int,
        map['count'] as int? ?? 0,
      );
    });
    _socket!.on('conversation:read', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onConversationRead?.call(
        map['conversationId'] as int,
      );
    });
    _socket!.on('conversation:favorite', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onFavoriteChange?.call(
        map['conversationId'] as int,
        map['isFavorite'] == true,
      );
    });
    _socket!.onDisconnect((_) => debugPrint('Socket déconnecté'));
    _socket!.connect();
  }

  void sendMessage({
    int? conversationId,
    int? toUserId,
    required String type,
    String? content,
    int? mediaId,
    bool viewOnce = false,
  }) {
    _socket?.emit('message:send', {
      if (conversationId != null) 'conversationId': conversationId,
      if (toUserId != null) 'toUserId': toUserId,
      'type': type,
      'content': content,
      'mediaId': mediaId,
      'viewOnce': viewOnce,
    });
  }

  void markRead(int messageId) {
    _socket?.emit('message:read', {'messageId': messageId});
  }

  void markConversationRead(int conversationId) {
    _socket?.emit('conversation:read', {'conversationId': conversationId});
  }

  void setFavorite(int conversationId, bool isFavorite) {
    _socket?.emit('conversation:favorite', {
      'conversationId': conversationId,
      'isFavorite': isFavorite,
    });
  }

  void mediaViewed({required int mediaId, required int ownerId}) {
    _socket?.emit('media:viewed', {'mediaId': mediaId, 'ownerId': ownerId});
  }

  void confirmMedia({required int mediaId, required int ownerId}) {
    _socket?.emit('media:viewed', {'mediaId': mediaId, 'ownerId': ownerId});
  }

  void requestConversations() {
    _socket?.emit('conversations:list');
  }

  void dispose() {
    _socket?.dispose();
  }
}