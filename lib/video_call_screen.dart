import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'calling_provider.dart';

class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final callingProvider = context.read<CallingProvider>();
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.blue,
            child: RTCVideoView(callingProvider.remoteRenderer),
          ),
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              // color: Colors.red,
              height: size.height * 0.3,
              width: size.width * 0.35,
              child: RTCVideoView(callingProvider.localRenderer),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Colors.red,
                  ),
                  onPressed: () async {
                    await context.read<CallingProvider>().endCall().then((_) {
                      Navigator.pop(context);
                    });
                  },
                  child: Icon(Icons.call_end),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
