import 'package:flutter/material.dart';
import 'custom_relay_session_screen.dart';

class CameraSenderScreen extends StatelessWidget {
  const CameraSenderScreen({super.key, this.remote = false});
  final bool remote;

  @override
  Widget build(BuildContext context) =>
      CustomRelaySessionScreen(cameraRole: true, remote: remote);
}
