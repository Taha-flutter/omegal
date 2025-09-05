import 'package:flutter/material.dart';

Future<void> showReconnectDialog({
  required BuildContext context,
  required VoidCallback onReconnect,
}) async {
  return showDialog(
    context: context,
    barrierDismissible: false, // user must choose
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Connection Lost"),
        content: const Text(
          "Your connection to the server was lost. Would you like to reconnect?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // dismiss only
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              onReconnect(); // trigger reconnect callback
            },
            child: const Text("Reconnect"),
          ),
        ],
      );
    },
  );
}
