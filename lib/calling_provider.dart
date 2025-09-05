import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:live_video_call_app/cp_print.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum MatchingState { idle, connecting, waiting, matched, inCall, callEnded }

class CallingProvider extends ChangeNotifier {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  late MediaStream localMediaStream;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? peerConnection;
  WebSocketChannel? channel;
  bool signaling = false;

  // New properties for matching system
  MatchingState matchingState = MatchingState.idle;
  String? roomId;
  String? username;
  String statusMessage = '';
  bool isCaller = false;

  Future<void> init(BuildContext context) async {
    await localRenderer.initialize();
    localMediaStream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });
    localRenderer.srcObject = localMediaStream;
    notifyListeners();
    // try {
    //   await startSignaling(context);
    // } catch (e) {
    //   EasyLoading.showError(e.toString());
    //   // showReconnectDialog(context: context, onReconnect: () async {});
    // }
  }

  Future<void> startSignaling(BuildContext context) async {
    signaling = true;
    matchingState = MatchingState.connecting;
    statusMessage = 'Connecting to server...';
    notifyListeners();
    try {
      channel =
          await Future<WebSocketChannel>.delayed(
            Duration.zero,
            () => WebSocketChannel.connect(
              Uri.parse("ws://192.168.0.104:8080/ws"),
            ),
          ).timeout(
            const Duration(seconds: 5), // ⏳ 5 second timeout
            onTimeout: () {
              throw "WebSocket connection timed out";
            },
          );
      channel?.stream.listen((message) async {
        _handelWebSocketMessage(message);
      });
    } catch (e) {
      matchingState = MatchingState.idle;
      statusMessage = 'Connection failed';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> joinWaitingRoom(String username) async {
    if (channel == null) {
      throw "Not connected to server";
    }

    print('Joining waiting room with username: $username');
    this.username = username;
    matchingState = MatchingState.waiting;
    statusMessage = 'Joining waiting room...';
    notifyListeners();

    final message = {'type': 'join_waiting', 'Username': username};
    print('Sending join_waiting message: $message');

    channel?.sink.add(jsonEncode(message));

    // Add a timeout to prevent getting stuck
    Future.delayed(Duration(seconds: 3), () {
      if (matchingState == MatchingState.waiting &&
          statusMessage == 'Joining waiting room...') {
        print('Timeout waiting for server response');
        statusMessage = 'Connection timeout. Please try again.';
        matchingState = MatchingState.idle;
        notifyListeners();
      }
    });
  }

  Future<void> leaveWaitingRoom() async {
    if (channel == null) return;

    final message = {'type': 'leave_waiting'};

    channel?.sink.add(jsonEncode(message));

    matchingState = MatchingState.idle;
    statusMessage = '';
    notifyListeners();
  }

  void _handelWebSocketMessage(dynamic message) async {
    print('Received WebSocket message: $message');
    var data = jsonDecode(message);

    // Handle new message types from server
    if (data["type"] == "connected") {
      print('Received connected message');
      statusMessage = 'Connected to server! Ready to find a partner.';
      notifyListeners();
    } else if (data["type"] == "waiting") {
      print('Received waiting message: ${data["data"]}');
      statusMessage = data["data"] ?? 'Waiting for another user...';
      notifyListeners();
    } else if (data["type"] == "matched") {
      print('Received matched message');
      roomId = data["room_id"];
      matchingState = MatchingState.matched;
      statusMessage = 'Matched! Starting call...';
      notifyListeners();

      // Start WebRTC connection
      await _initializePeerConnection();
      await _createOffer();
    } else if (data["type"] == "call_ended") {
      print('Received call_ended message');
      matchingState = MatchingState.callEnded;
      statusMessage = 'Call ended by partner';
      await endCall();
      notifyListeners();
    } else if (data["sdp"] != null) {
      print('Received SDP message');
      await _handelSDP(data);
    } else if (data["candidate"] != null) {
      print('Received ICE candidate message');
      await handelIceCandidate(data);
    } else {
      print('Unknown message type: ${data["type"]}');
    }
  }

  Future<void> _initializePeerConnection() async {
    if (peerConnection != null) return;

    peerConnection = await createPeerConnection({});
    for (var track in localMediaStream.getTracks()) {
      peerConnection!.addTrack(track, localMediaStream);
    }

    peerConnection?.onTrack = (event) {
      remoteRenderer.srcObject = event.streams[0];
      matchingState = MatchingState.inCall;
      statusMessage = 'Connected!';
      notifyListeners();
    };

    peerConnection?.onIceCandidate = (candidate) {
      print('Sending ICE candidate');
      channel?.sink.add(
        jsonEncode({
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };

    peerConnection?.onConnectionState = (state) {
      CP.green('Connection state changed: $state');
    };

    peerConnection?.onIceConnectionState = (state) {
      CP.green('ICE connection state changed: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        Future.delayed(Duration(seconds: 1), () async {
          final streams = peerConnection?.getRemoteStreams();
          if (streams != null && streams.isNotEmpty) {
            remoteRenderer.srcObject = streams[0];
            matchingState = MatchingState.inCall;
            statusMessage = 'Connected!';
            notifyListeners();
          }
        });
      }
    };
  }

  Future<void> _createOffer() async {
    if (peerConnection == null) return;

    isCaller = true;
    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    channel?.sink.add(
      jsonEncode({'type': 'sdp', 'sdp': offer.sdp, 'sdpType': offer.type}),
    );
  }

  Future<void> _handelSDP(dynamic data) async {
    if (peerConnection == null) {
      await _initializePeerConnection();
    }

    var sdp = RTCSessionDescription(data["sdp"], data["type"]);
    if (data["type"] == "offer") {
      await peerConnection!.setRemoteDescription(sdp);
      final answer = await peerConnection!.createAnswer();
      await peerConnection?.setLocalDescription(answer);
      channel?.sink.add(
        jsonEncode({'type': 'sdp', 'sdp': answer.sdp, 'sdpType': answer.type}),
      );
    } else if (data["type"] == "answer") {
      await peerConnection?.setRemoteDescription(sdp);
    }
  }

  Future<void> handelIceCandidate(dynamic data) async {
    if (peerConnection != null) {
      await peerConnection!.addCandidate(
        RTCIceCandidate(
          data["candidate"],
          data["sdpMid"],
          data["sdpMLineIndex"],
        ),
      );
    }
  }

  Future<void> endCall() async {
    try {
      // Notify server that call is ending
      if (channel != null) {
        channel?.sink.add(jsonEncode({'type': 'end_call'}));
      }

      await peerConnection?.close();
      peerConnection = null;
      remoteRenderer.srcObject = null;

      // Reset state
      matchingState = MatchingState.idle;
      roomId = null;
      isCaller = false;
      statusMessage = '';
      notifyListeners();
    } catch (e) {
      // Log error but don't rethrow to ensure navigation still works
      print('Error in endCall: $e');
      // Still reset state even if there was an error
      matchingState = MatchingState.idle;
      roomId = null;
      isCaller = false;
      statusMessage = '';
      notifyListeners();
    }
  }

  void dispose() {
    endCall();
    localRenderer.dispose();
    remoteRenderer.dispose();
    channel?.sink.close();
    super.dispose();
  }
}
