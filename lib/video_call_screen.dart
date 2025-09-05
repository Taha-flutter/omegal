import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'calling_provider.dart';

class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Consumer<CallingProvider>(
        builder: (context, callingProvider, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Remote video with fallback
              Container(
                color: Colors.black,
                child: callingProvider.remoteRenderer.srcObject != null
                    ? RTCVideoView(callingProvider.remoteRenderer)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              size: 64,
                              color: Colors.white54,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Waiting for remote video...',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Connection: ${callingProvider.matchingState.name}',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Debug: ${callingProvider.getRemoteRendererDebugInfo()['hasSrcObject'] ? 'Has Stream' : 'No Stream'}',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  height: size.height * 0.3,
                  width: size.width * 0.35,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: RTCVideoView(callingProvider.localRenderer),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Refresh button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(15),
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        callingProvider.refreshRemoteStream();
                      },
                      child: Icon(Icons.refresh, size: 20),
                    ),
                    SizedBox(width: 10),
                    // Debug button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(15),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () {
                        final debugInfo = callingProvider
                            .getRemoteRendererDebugInfo();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Debug Info'),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: debugInfo.entries.map((entry) {
                                  return Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: Text('${entry.key}: ${entry.value}'),
                                  );
                                }).toList(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Icon(Icons.bug_report, size: 20),
                    ),
                    SizedBox(width: 20),
                    // End call button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(20),
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        await callingProvider.endCall().then((_) {
                          Navigator.pop(context);
                        });
                      },
                      child: Icon(Icons.call_end),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
