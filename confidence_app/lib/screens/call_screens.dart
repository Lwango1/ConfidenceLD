import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final int fromUserId;
  final String displayName;
  final String? avatar;
  final bool isVideo;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.fromUserId,
    required this.displayName,
    this.avatar,
    required this.isVideo,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed => '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

void _accept() async {
    await CallService.instance
        .accept(IncomingCall(callId: widget.callId, fromUserId: widget.fromUserId, isVideo: widget.isVideo));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ActiveCallScreen(
        callId: widget.callId,
        peerId: widget.fromUserId,
        displayName: widget.displayName,
        avatar: widget.avatar,
        isVideo: widget.isVideo,
        initiatedByMe: false,
      ),
    ));
  }

  void _reject() {
    CallService.instance
        .reject(IncomingCall(callId: widget.callId, fromUserId: widget.fromUserId, isVideo: widget.isVideo));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF1F2A3A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFF2C5364),
              backgroundImage: widget.avatar != null
                  ? NetworkImage('${ApiConfig.baseUrl}${widget.avatar}')
                  : null,
              child: widget.avatar == null
                  ? Text(
                      widget.displayName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.displayName,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isVideo ? 'Appel vidéo entrant...' : 'Appel vocal entrant...',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _elapsed,
              style: const TextStyle(color: Colors.white38, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const Spacer(flex: 3),
            SizedBox(
              width: size.width * 0.5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BigButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    label: 'Refuser',
                    onTap: _reject,
                  ),
                  _BigButton(
                    icon: widget.isVideo ? Icons.videocam : Icons.call,
                    color: const Color(0xFF2ECC71),
                    label: widget.isVideo ? 'Accepter' : 'Accepter',
                    onTap: _accept,
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class ActiveCallScreen extends StatefulWidget {
  final String callId;
  final int peerId;
  final String displayName;
  final String? avatar;
  final bool isVideo;
  final bool initiatedByMe;
  const ActiveCallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.displayName,
    this.avatar,
    required this.isVideo,
    required this.initiatedByMe,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  int _seconds = 0;
  Timer? _timer;
  bool _micOff = false;
  bool _camOff = false;
  bool _speakerOn = true;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connected) setState(() => _seconds++);
    });
  }

  Future<void> _init() async {
    final svc = CallService.instance;
    try {
      await _localRenderer.initialize();
    } catch (_) {}
    try {
      await _remoteRenderer.initialize();
    } catch (_) {}
    svc.onConnectionFailed = _hangup;
    svc.onCallEnded = _hangup;
    svc.onCallRejected = _hangup;
    svc.onRemoteStreamAttached = () {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = svc.remoteStream;
        });
      }
    };
    if (widget.initiatedByMe) {
      final err = await svc.startCall(toUserId: widget.peerId, isVideo: widget.isVideo);
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err == 'offline'
                ? 'Contact hors ligne'
                : err == 'busy'
                    ? 'Contact déjà en ligne'
                    : err == 'micro_error'
                        ? 'Autorisez le micro et la caméra'
                        : 'Appel impossible'),
          ));
          Navigator.of(context).pop();
        }
        return;
      }
    }
    _localRenderer.srcObject = svc.localStream;
    _remoteRenderer.srcObject = svc.remoteStream;
    svc.onCallStart = () {
      if (mounted) {
        setState(() => _connected = true);
      }
    };
    if (!widget.initiatedByMe) {
      setState(() => _connected = true);
    }
    _refreshStreams();
  }

  void _refreshStreams() {
    if (!mounted) return;
    setState(() {
      _localRenderer.srcObject = CallService.instance.localStream;
      _remoteRenderer.srcObject = CallService.instance.remoteStream;
    });
  }

  String get _elapsed => '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  void _hangup() {
    CallService.instance.endCall();
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _toggleMic() {
    final stream = CallService.instance.localStream;
    if (stream == null) return;
    setState(() => _micOff = !_micOff);
    stream.getAudioTracks().forEach((t) => t.enabled = !_micOff);
  }

  void _toggleCam() {
    final stream = CallService.instance.localStream;
    if (stream == null) return;
    setState(() => _camOff = !_camOff);
    stream.getVideoTracks().forEach((t) => t.enabled = !_camOff);
  }

  void _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await Helper.setSpeakerphoneOn(_speakerOn);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF17202A),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: widget.isVideo
                  ? RTCVideoView(_remoteRenderer, mirror: false, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: const Color(0xFF2C5364),
                          backgroundImage: widget.avatar != null
                              ? NetworkImage('${ApiConfig.baseUrl}${widget.avatar}')
                              : null,
                          child: widget.avatar == null
                              ? Text(
                                  widget.displayName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontSize: 40, color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.displayName,
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _connected ? _elapsed : 'Connexion en cours...',
                          style: const TextStyle(color: Colors.white70, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
            ),
            if (widget.isVideo && _connected)
              Positioned(
                top: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 110,
                    height: 160,
                    color: Colors.black,
                    child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: size.height * 0.55,
              child: Text(
                _connected ? _elapsed : 'Connexion en cours...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: _micOff ? Icons.mic_off : Icons.mic,
                    color: _micOff ? Colors.grey.shade700 : Colors.white12,
                    onTap: _toggleMic,
                  ),
                  if (widget.isVideo)
                    _ControlButton(
                      icon: _camOff ? Icons.videocam_off : Icons.videocam,
                      color: _camOff ? Colors.grey.shade700 : Colors.white12,
                      onTap: _toggleCam,
                    ),
                  _ControlButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                    color: Colors.white12,
                    onTap: _toggleSpeaker,
                  ),
                  _ControlButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    onTap: _hangup,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _BigButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ControlButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}