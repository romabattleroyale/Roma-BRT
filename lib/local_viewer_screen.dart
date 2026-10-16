import 'package:flutter/material.dart';
import 'stream_session_screen.dart';

class LocalViewerScreen extends StatelessWidget {
  const LocalViewerScreen({super.key, this.remote = false});
  final bool remote;

  @override
  Widget build(BuildContext context) =>
      StreamSessionScreen(role: StreamRole.viewer, remote: remote);
}
