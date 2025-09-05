# Omegle-like Video Chat App

A Flutter application that allows users to connect with random strangers for video calls, similar to Omegle.

## Features

- **Random Matching**: Users are automatically matched with other users who are looking for a chat
- **Video Calling**: Full WebRTC video calling with audio and video
- **Real-time Communication**: WebSocket-based signaling server
- **Modern UI**: Clean and intuitive user interface
- **Cross-platform**: Works on Android, iOS, and Web

## How it Works

1. **Connect**: Users first connect to the signaling server
2. **Enter Name**: Users enter their name to identify themselves
3. **Find Partner**: Users click "Find a Partner" to join the waiting room
4. **Automatic Matching**: When 2 users are waiting, they are automatically matched
5. **Video Call**: Both users are navigated to the video call screen
6. **End Call**: Users can end the call at any time

## Setup Instructions

### Prerequisites

- Flutter SDK (latest stable version)
- Go (for the signaling server)
- Android Studio / Xcode (for mobile development)

### Server Setup

1. Navigate to the server directory:

   ```bash
   cd server
   ```

2. Install Go dependencies:

   ```bash
   go mod tidy
   ```

3. Run the signaling server:

   ```bash
   go run main.go
   ```

   The server will start on port 8080.

### Flutter App Setup

1. Install Flutter dependencies:

   ```bash
   flutter pub get
   ```

2. Update the WebSocket URL in `lib/calling_provider.dart` if needed:

   ```dart
   Uri.parse("ws://YOUR_SERVER_IP:8080/ws")
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Usage

1. **Start the server** first (see Server Setup above)
2. **Launch the Flutter app** on two different devices or emulators
3. **Enter your name** in the text field
4. **Click "Connect to Server"** to establish connection
5. **Click "Find a Partner"** to join the waiting room
6. **Wait for matching** - when another user joins, you'll be automatically matched
7. **Start video calling** - both users will be navigated to the video call screen
8. **End the call** by clicking the red phone button

## Architecture

### Client Side (Flutter)

- **CallingProvider**: Manages WebRTC connections and state
- **Homepage**: Main UI for connecting and finding partners
- **VideoCallScreen**: Video calling interface
- **WebSocket**: Real-time communication with server

### Server Side (Go)

- **WebSocket Server**: Handles client connections
- **Room Management**: Creates and manages video call rooms
- **User Matching**: Matches users in waiting room
- **Message Forwarding**: Forwards WebRTC signaling between users

## Technologies Used

- **Flutter**: Cross-platform mobile framework
- **WebRTC**: Real-time communication
- **Go**: Backend signaling server
- **WebSocket**: Real-time messaging
- **Provider**: State management

## Network Requirements

- Both users need to be on the same network or have proper port forwarding
- Server IP should be accessible from client devices
- WebRTC requires STUN/TURN servers for NAT traversal (currently using default STUN servers)

## Troubleshooting

1. **Connection Issues**: Make sure the server is running and accessible
2. **No Video**: Check camera permissions
3. **No Audio**: Check microphone permissions
4. **Matching Issues**: Ensure both users are connected to the same server

## Future Enhancements

- Add text chat functionality
- Implement user reporting system
- Add video filters and effects
- Support for group video calls
- User profiles and preferences
- Better NAT traversal with TURN servers
