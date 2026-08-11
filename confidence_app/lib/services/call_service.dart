import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

class IncomingCall {
  final String callId;
  final int fromUserId;
  final bool isVideo;
  final String fromDisplayName;
  final String? fromAvatar;
  IncomingCall({
    required this.callId,
    required this.fromUserId,
    required this.isVideo,
    this.fromDisplayName = 'Utilisateur',
    this.fromAvatar,
  });
}

class CallService {
  CallService._();

  static final CallService instance = CallService._();

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  io.Socket? _socket;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isInCall => _callId != null;

  String? _callId;
  int? _peerId;
  bool _callEnded = false;

  void Function(IncomingCall call)? onIncomingCall;
  VoidCallback? onCallStart;
  VoidCallback? onCallEnded;
  VoidCallback? onCallRejected;
  VoidCallback? onPeerBusy;
  VoidCallback? onConnectionFailed;
  VoidCallback? onRemoteStreamAttached;

  void init() {
    if (_socket != null) return;
    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': ApiService.token})
          .build(),
    );
    _socket!.onConnect((_) => debugPrint('CallService socket connecté'));
    _socket!.on('call:incoming', (data) {
      final map = (data as Map).cast<String, dynamic>();
      onIncomingCall?.call(IncomingCall(
        callId: map['callId'] as String,
        fromUserId: map['fromUserId'] as int,
        isVideo: map['isVideo'] == true,
        fromDisplayName: map['fromDisplayName'] as String? ?? 'Utilisateur',
        fromAvatar: map['fromAvatar'] as String?,
      ));
    });
    _socket!.on('call:accepted', (data) {
      final map = (data as Map).cast<String, dynamic>();
      if (map['callId'] != _callId) return;
      onCallStart?.call();
      _negotiate();
    });
    _socket!.on('call:rejected', (data) {
      final map = (data as Map).cast<String, dynamic>();
      if (map['callId'] != _callId) return;
      _teardown();
      onCallRejected?.call();
    });
    _socket!.on('call:busy', (data) {
      final map = (data as Map).cast<String, dynamic>();
      if (map['callId'] != _callId) return;
      _teardown();
      onPeerBusy?.call();
    });
    _socket!.on('call:signal', (data) async {
      final map = (data as Map).cast<String, dynamic>();
      if (map['callId'] != _callId) return;
      try {
        final signal = map['signal'] as Map;
        if (signal['type'] == 'offer') {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'] as String, 'offer'),
          );
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          _emit('call:signal', {
            'callId': _callId,
            'toUserId': _peerId,
            'signal': {'type': 'answer', 'sdp': answer.sdp},
          });
        } else if (signal['type'] == 'answer') {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(signal['sdp'] as String, 'answer'),
          );
        } else if (signal['candidate'] != null) {
          await _pc!.addCandidate(
            RTCIceCandidate(
              signal['candidate'] as String,
              signal['sdpMid'] as String?,
              signal['sdpMLineIndex'] as int?,
            ),
          );
        }
      } catch (e) {
        debugPrint('call:signal erreur: $e');
      }
    });
    _socket!.on('call:ended', (data) {
      final map = (data as Map).cast<String, dynamic>();
      if (map['callId'] != _callId) return;
      _teardown();
      onCallEnded?.call();
    });
    _socket!.onDisconnect((_) {});
    _socket!.connect();
  }

  void _emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  Future<RTCPeerConnection> _createPeer() async {
    final pc = await createPeerConnection(_iceServers);
    pc.onTrack = (event) {
      _remoteStream = event.streams.isNotEmpty ? event.streams[0] : null;
      onRemoteStreamAttached?.call();
    };
    pc.onIceCandidate = (candidate) {
      if (_callEnded) return;
      _emit('call:signal', {
        'callId': _callId,
        'toUserId': _peerId,
        'signal': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    pc.onConnectionState = (state) {
      debugPrint('PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (!_callEnded) {
          _teardown();
          onConnectionFailed?.call();
        }
      }
    };
    return pc;
  }

  Future<void> _negotiate() async {
    try {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _emit('call:signal', {
        'callId': _callId,
        'toUserId': _peerId,
        'signal': {'type': 'offer', 'sdp': offer.sdp},
      });
    } catch (e) {
      debugPrint('negotiate erreur: $e');
    }
  }

  Future<String?> startCall({
    required int toUserId,
    required bool isVideo,
  }) async {
    init();
    _callEnded = false;
    _peerId = toUserId;
    _callId = '${DateTime.now().millisecondsSinceEpoch}_${ApiService.userId}';

    final completer = Completer<String?>();

    _socket!.emitWithAck('call:offer', {
      'toUserId': toUserId,
      'callId': _callId,
      'isVideo': isVideo,
    }, ack: (res) async {
      final ok = res['ok'] == true;
      if (!ok) {
        _callId = null;
        _peerId = null;
        completer.complete(res['error'] as String? ?? 'error');
        return;
      }
      try {
        _pc = await _createPeer();
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': isVideo,
        });
        _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));
        completer.complete(null);
      } catch (e) {
        _socket!.emit('call:end', {
          'callId': _callId,
          'toUserId': toUserId,
        });
        _callId = null;
        _peerId = null;
        completer.complete('micro_error');
      }
    });

    return completer.future;
  }

  Future<void> accept(IncomingCall call) async {
    init();
    _callEnded = false;
    _callId = call.callId;
    _peerId = call.fromUserId;
    try {
      _pc = await _createPeer();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': call.isVideo,
      });
      _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));
      _emit('call:accept', {'callId': _callId, 'toUserId': _peerId});
    } catch (e) {
      debugPrint('accept erreur: $e');
      reject(call);
    }
  }

  void reject(IncomingCall call) {
    _callId = call.callId;
    _peerId = call.fromUserId;
    _emit('call:reject', {'callId': call.callId, 'toUserId': call.fromUserId});
    _callId = null;
    _peerId = null;
  }

  void endCall() {
    if (_callEnded) return;
    _callEnded = true;
    if (_callId != null && _peerId != null) {
      _emit('call:end', {'callId': _callId, 'toUserId': _peerId});
    }
    _teardown();
  }

  void _teardown() {
    _callEnded = true;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    try {
      _pc?.close();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
    _pc = null;
  }
}