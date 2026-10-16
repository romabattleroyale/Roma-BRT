import 'package:flutter/material.dart';
import 'stream_session_screen.dart';

class CameraSenderScreen extends StatelessWidget {
  const CameraSenderScreen({super.key, this.remote = false});
  final bool remote;

  @override
  Widget build(BuildContext context) =>
      StreamSessionScreen(role: StreamRole.camera, remote: remote);
}
