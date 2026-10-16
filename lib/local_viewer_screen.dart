import 'package:flutter/material.dart';
import 'custom_relay_session_screen.dart';

class LocalViewerScreen extends StatelessWidget {
  const LocalViewerScreen({super.key, this.remote = false});
  final bool remote;

  @override
  Widget build(BuildContext context) =>
      CustomRelaySessionScreen(cameraRole: false, remote: remote);
}
