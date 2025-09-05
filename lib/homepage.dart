import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:live_video_call_app/calling_provider.dart';
import 'package:live_video_call_app/video_call_screen.dart';
import 'package:provider/provider.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final TextEditingController nameController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    context.read<CallingProvider>().init(context);

    // Listen for matching state changes
    context.read<CallingProvider>().addListener(_onMatchingStateChanged);
  }

  @override
  void dispose() {
    context.read<CallingProvider>().removeListener(_onMatchingStateChanged);
    super.dispose();
  }

  void _onMatchingStateChanged() {
    final provider = context.read<CallingProvider>();

    // Navigate to video call screen when matched
    if (provider.matchingState == MatchingState.matched ||
        provider.matchingState == MatchingState.inCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => VideoCallScreen()),
          );
        }
      });
    }

    // Navigate back to home when call ends
    if (provider.matchingState == MatchingState.callEnded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: Text('Omegle-like Video Chat'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status message
              Consumer<CallingProvider>(
                builder: (context, provider, child) {
                  if (provider.statusMessage.isNotEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      margin: EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: _getStatusColor(provider.matchingState),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        provider.statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),

              // Local video preview
              Consumer<CallingProvider>(
                builder: (context, provider, child) {
                  return Container(
                    height: size.height * 0.3,
                    width: size.width * 0.8,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: RTCVideoView(provider.localRenderer),
                    ),
                  );
                },
              ),

              SizedBox(height: 30),

              // Name input field
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: nameController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter your name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Action buttons
              Consumer<CallingProvider>(
                builder: (context, provider, child) {
                  return Column(
                    children: [
                      // Main action button - combines connect and find partner
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (provider.matchingState == MatchingState.idle) {
                              // Check if name is provided
                              if (nameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Please enter your name first',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              // First connect to server
                              try {
                                await provider.startSignaling(context);
                                // After connecting, automatically join waiting room
                                await Future.delayed(
                                  Duration(milliseconds: 500),
                                ); // Small delay to show connection status
                                await provider.joinWaitingRoom(
                                  nameController.text.trim(),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Connection failed: $e'),
                                  ),
                                );
                              }
                            } else if (provider.matchingState ==
                                MatchingState.waiting) {
                              // Cancel waiting
                              provider.leaveWaitingRoom();
                            }
                          },
                          icon: Icon(
                            provider.matchingState == MatchingState.idle
                                ? Icons.search
                                : provider.matchingState ==
                                      MatchingState.waiting
                                ? Icons.cancel
                                : Icons.wifi,
                          ),
                          label: Text(
                            provider.matchingState == MatchingState.idle
                                ? 'Find a Partner'
                                : provider.matchingState ==
                                      MatchingState.waiting
                                ? 'Cancel Search'
                                : provider.matchingState ==
                                      MatchingState.connecting
                                ? 'Connecting...'
                                : 'Connected',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            backgroundColor:
                                provider.matchingState == MatchingState.idle
                                ? Theme.of(context).colorScheme.primary
                                : provider.matchingState ==
                                      MatchingState.waiting
                                ? Colors.orange
                                : provider.matchingState ==
                                      MatchingState.connecting
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(MatchingState state) {
    switch (state) {
      case MatchingState.connecting:
        return Colors.blue;
      case MatchingState.waiting:
        return Colors.orange;
      case MatchingState.matched:
        return Colors.green;
      case MatchingState.inCall:
        return Colors.green;
      case MatchingState.callEnded:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
