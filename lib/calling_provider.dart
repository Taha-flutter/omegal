import 'dart:async';
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
    await remoteRenderer.initialize(); // Initialize remote renderer
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
              Uri.parse("ws://192.168.0.105:8080/ws"),
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
    print('=== WEBSOCKET MESSAGE RECEIVED ===');
    print('Raw message: $message');
    var data = jsonDecode(message);
    print('Parsed data: $data');

    // Handle new message types from server
    if (data["type"] == "connected") {
      print('✅ Received connected message');
      statusMessage = 'Connected to server! Ready to find a partner.';
      notifyListeners();
    } else if (data["type"] == "waiting") {
      print('⏳ Received waiting message: ${data["data"]}');
      statusMessage = data["data"] ?? 'Waiting for another user...';
      notifyListeners();
    } else if (data["type"] == "matched") {
      print('🎯 Received matched message');
      roomId = data["room_id"];
      matchingState = MatchingState.matched;
      statusMessage = 'Matched! Starting call...';
      notifyListeners();

      // Start WebRTC connection
      await _initializePeerConnection();

      // Check if we are the caller or answerer
      String role = data["data"] ?? "answerer";
      print('🎭 My role: $role');

      if (role == "caller") {
        isCaller = true;
        print('📞 I am the caller, creating offer...');
        await _createOffer();
      } else {
        isCaller = false;
        print('📱 I am the answerer, waiting for offer...');
        // Answerer waits for offer
      }
    } else if (data["type"] == "call_ended") {
      print('📴 Received call_ended message');
      matchingState = MatchingState.callEnded;
      statusMessage = 'Call ended by partner';
      await endCall();
      notifyListeners();
    } else if (data["sdp"] != null) {
      print('📋 Received SDP message: ${data["type"] ?? "unknown"}');
      // Handle different SDP message formats
      if (data["type"] == "sdp" && data["sdpType"] != null) {
        // Format: {type: "sdp", sdp: "...", sdpType: "offer"}
        data["type"] = data["sdpType"];
        print(
          '🔧 Converted SDP type from ${data["sdpType"]} to ${data["type"]}',
        );
      } else if (data["type"] == null) {
        // Fallback: assume it's an offer
        data["type"] = "offer";
        print('🔧 Assumed SDP type as offer');
      }
      await _handelSDP(data);
    } else if (data["candidate"] != null) {
      print('🧊 Received ICE candidate message');
      await handelIceCandidate(data);
    } else {
      print('❓ Unknown message type: ${data["type"]}');
      print('Full message data: $data');
    }
  }

  Future<void> _initializePeerConnection() async {
    if (peerConnection != null) return;

    try {
      print('Initializing peer connection...');
      peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      for (var track in localMediaStream.getTracks()) {
        await peerConnection!.addTrack(track, localMediaStream);
        print('Added track: ${track.kind}');
      }

      peerConnection?.onTrack = (event) {
        print('🎥 === ONTRACK EVENT TRIGGERED ===');
        print('Received remote track: ${event.track.kind}');
        print('Track ID: ${event.track.id}');
        print('Track enabled: ${event.track.enabled}');
        print('Number of streams: ${event.streams.length}');

        if (event.streams.isNotEmpty) {
          print('✅ Setting remote stream to renderer');
          remoteRenderer.srcObject = event.streams[0];
          print('Remote stream set. Stream ID: ${event.streams[0].id}');
          print('Remote stream tracks: ${event.streams[0].getTracks().length}');
          matchingState = MatchingState.inCall;
          statusMessage = 'Connected!';
          notifyListeners();
        } else {
          print('❌ No streams in track event');
        }
      };

      peerConnection?.onIceCandidate = (candidate) {
        print('Sending ICE candidate: ${candidate.candidate}');
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
        print('=== CONNECTION STATE CHANGED: $state ===');
        CP.green('Connection state changed: $state');

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          print('✅ PEER CONNECTION CONNECTED!');
          _checkAndSetRemoteStream();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          print('❌ PEER CONNECTION FAILED!');
          statusMessage = 'Connection failed';
          notifyListeners();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          print('⚠️ PEER CONNECTION DISCONNECTED!');
        }
      };

      peerConnection?.onIceConnectionState = (state) {
        print('=== ICE CONNECTION STATE CHANGED: $state ===');
        CP.green('ICE connection state changed: $state');

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          print('✅ ICE CONNECTION ESTABLISHED!');
          print('Checking for remote streams...');
          Future.delayed(Duration(seconds: 1), () async {
            _checkAndSetRemoteStream();
          });

          // Add periodic checks for remote stream
          Timer.periodic(Duration(seconds: 2), (timer) {
            print(
              'Periodic check: matchingState=${matchingState.name}, hasRemoteStream=${remoteRenderer.srcObject != null}',
            );
            if (matchingState == MatchingState.inCall &&
                remoteRenderer.srcObject == null) {
              _checkAndSetRemoteStream();
            } else if (remoteRenderer.srcObject != null) {
              print('Remote stream found, canceling periodic check');
              timer.cancel();
            }
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          print('❌ ICE CONNECTION FAILED!');
          statusMessage = 'ICE connection failed';
          notifyListeners();
        } else if (state ==
            RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          print('⚠️ ICE CONNECTION DISCONNECTED!');
        }
      };

      print('Peer connection initialized successfully');
    } catch (e) {
      print('Error initializing peer connection: $e');
      statusMessage = 'Failed to initialize connection: $e';
      notifyListeners();
    }
  }

  Future<void> _createOffer() async {
    if (peerConnection == null) return;

    try {
      print('Creating offer...');
      isCaller = true;
      final offer = await peerConnection!.createOffer();
      await peerConnection!.setLocalDescription(offer);
      print('Offer created and set as local description');

      channel?.sink.add(
        jsonEncode({'type': 'sdp', 'sdp': offer.sdp, 'sdpType': offer.type}),
      );
      print('Offer sent to peer');
    } catch (e) {
      print('Error creating offer: $e');
      statusMessage = 'Failed to create offer: $e';
      notifyListeners();
    }
  }

  Future<void> _handelSDP(dynamic data) async {
    try {
      if (peerConnection == null) {
        print('Peer connection is null, initializing...');
        await _initializePeerConnection();
      }

      print('Handling SDP: ${data["type"]}');
      print('SDP data: ${data["sdp"]?.substring(0, 100)}...');
      var sdp = RTCSessionDescription(data["sdp"], data["type"]);

      if (data["type"] == "offer") {
        print('Received offer, creating answer...');
        print('Setting remote description...');
        await peerConnection!.setRemoteDescription(sdp);
        print('Remote description set successfully');

        print('Creating answer...');
        final answer = await peerConnection!.createAnswer();
        print('Answer created: ${answer.type}');

        print('Setting local description...');
        await peerConnection?.setLocalDescription(answer);
        print('Local description set successfully');

        print('Sending answer to peer...');
        channel?.sink.add(
          jsonEncode({
            'type': 'sdp',
            'sdp': answer.sdp,
            'sdpType': answer.type,
          }),
        );
        print('Answer sent to peer');
      } else if (data["type"] == "answer") {
        print('Received answer, setting remote description...');
        await peerConnection?.setRemoteDescription(sdp);
        print('Remote description set successfully');
      }
    } catch (e) {
      print('Error handling SDP: $e');
      print('Stack trace: ${StackTrace.current}');
      statusMessage = 'Failed to handle SDP: $e';
      notifyListeners();
    }
  }

  Future<void> handelIceCandidate(dynamic data) async {
    try {
      if (peerConnection != null) {
        print('Adding ICE candidate: ${data["candidate"]}');
        print('ICE candidate sdpMid: ${data["sdpMid"]}');
        print('ICE candidate sdpMLineIndex: ${data["sdpMLineIndex"]}');

        final candidate = RTCIceCandidate(
          data["candidate"],
          data["sdpMid"],
          data["sdpMLineIndex"],
        );

        await peerConnection!.addCandidate(candidate);
        print('ICE candidate added successfully');
      } else {
        print(
          'ERROR: Peer connection is null when trying to add ICE candidate',
        );
      }
    } catch (e) {
      print('Error adding ICE candidate: $e');
      print('Stack trace: ${StackTrace.current}');
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

  // Method to check and set remote stream
  void _checkAndSetRemoteStream() {
    if (peerConnection != null) {
      final streams = peerConnection!.getRemoteStreams();
      print('Checking remote streams: ${streams.length}');
      if (streams.isNotEmpty && remoteRenderer.srcObject == null) {
        print('Setting remote stream from getRemoteStreams()');
        remoteRenderer.srcObject = streams[0];
        matchingState = MatchingState.inCall;
        statusMessage = 'Connected!';
        notifyListeners();
      }
    }
  }

  // Manual refresh method for debugging
  void refreshRemoteStream() {
    print('Manual refresh requested');
    _checkAndSetRemoteStream();
    notifyListeners();
  }

  // Debug method to check remote renderer state
  Map<String, dynamic> getRemoteRendererDebugInfo() {
    final remoteStreams = peerConnection?.getRemoteStreams() ?? [];
    final localStreams = peerConnection?.getLocalStreams() ?? [];

    return {
      'hasSrcObject': remoteRenderer.srcObject != null,
      'streamId': remoteRenderer.srcObject?.id ?? 'null',
      'trackCount': remoteRenderer.srcObject?.getTracks().length ?? 0,
      'matchingState': matchingState.name,
      'isCaller': isCaller,
      'peerConnectionState':
          peerConnection?.connectionState?.toString() ?? 'null',
      'iceConnectionState':
          peerConnection?.iceConnectionState?.toString() ?? 'null',
      'remoteStreamsCount': remoteStreams.length,
      'localStreamsCount': localStreams.length,
      'peerConnectionExists': peerConnection != null,
      'channelConnected': channel != null,
      'roomId': roomId ?? 'null',
      'statusMessage': statusMessage,
    };
  }

  void dispose() {
    endCall();
    localRenderer.dispose();
    remoteRenderer.dispose();
    channel?.sink.close();
    super.dispose();
  }
}
