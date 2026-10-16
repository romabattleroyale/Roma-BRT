import 'package:flutter/material.dart';
import 'camera_sender_screen.dart';
import 'local_viewer_screen.dart';

const _bg = Color(0xFF080B12);
const _panel = Color(0xFF111824);
const _panel2 = Color(0xFF192435);
const _violet = Color(0xFF9B7BFF);
const _cyan = Color(0xFF48E5F2);
const _muted = Color(0xFF8D9AAF);
const _amber = Color(0xFFFFC66D);

enum _Role { camera, viewer }

class ConnectionSetupScreen extends StatefulWidget {
  const ConnectionSetupScreen({super.key});
  @override
  State<ConnectionSetupScreen> createState() => _ConnectionSetupScreenState();
}

class _ConnectionSetupScreenState extends State<ConnectionSetupScreen>
    with SingleTickerProviderStateMixin {
  _Role _role = _Role.viewer;
  bool _remoteMode = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(backgroundColor: _bg, title: const Text('Collega i dispositivi')),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF20213D), _panel, Color(0xFF101D2B)]),
          border: Border.all(color: _violet.withValues(alpha: .32)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedBuilder(animation: _pulse, builder: (context, child) => Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: .08 + _pulse.value * .12),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .05 + _pulse.value * .18), blurRadius: 22)],
            ),
            child: const Icon(Icons.hub_rounded, color: _cyan, size: 29),
          )),
          const SizedBox(height: 18),
          const Text('Un sistema. Due dispositivi.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          const SizedBox(height: 8),
          const Text('Scegli quale telefono invia il video e quale lo visualizza. Il telefono invia fotogrammi JPEG al relay personalizzato, che li inoltra al monitor. È un prototipo video senza audio.', style: TextStyle(color: _muted, height: 1.5)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .2), borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.circle, color: _amber, size: 8), SizedBox(width: 8),
              Expanded(child: Text('NON COLLEGATO · configurazione iniziale', style: TextStyle(color: _amber, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .4))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 22),
      const Text('Questo telefono sarà…', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _roleCard(selected: _role == _Role.camera, icon: Icons.videocam_rounded, title: 'Telecamera', subtitle: 'Invia il video', onTap: () => setState(() => _role = _Role.camera))),
        const SizedBox(width: 10),
        Expanded(child: _roleCard(selected: _role == _Role.viewer, icon: Icons.phone_android_rounded, title: 'Monitor', subtitle: 'Guarda il video', onTap: () => setState(() => _role = _Role.viewer))),
      ]),
      const SizedBox(height: 22),
      const Text('Tipo di connessione', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      _modeTile(selected: !_remoteMode, icon: Icons.wifi_rounded, title: 'Rete Wi-Fi locale', subtitle: "Per il primo test: entrambi i telefoni sullo stesso Wi-Fi. Il servizio WSS coordina l'abbinamento; il video tenta un percorso diretto tra i dispositivi.", onTap: () => setState(() => _remoteMode = false)),
      const SizedBox(height: 9),
      _modeTile(selected: _remoteMode, icon: Icons.public_rounded, title: 'Fuori casa · Internet', subtitle: 'Richiede un endpoint WSS pubblico e il relay JPEG raggiungibile da Internet.', onTap: () => setState(() => _remoteMode = true)),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.route_rounded, color: _violet), const SizedBox(width: 9),
            Expanded(child: Text(_remoteMode ? 'Percorso remoto selezionato' : 'Percorso locale selezionato', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Text(_remoteMode
            ? "Per la modalità remota configura un endpoint WSS pubblico e distribuisci il relay JPEG con TLS e autenticazione. Non è un servizio pronto all'uso finché il server non è pubblicato."
            : "Il video usa il relay JPEG personalizzato. Inserisci l'indirizzo WebSocket del relay; per una prova in rete locale puoi usare un server raggiungibile da entrambi i telefoni.",
            style: const TextStyle(color: _muted, height: 1.5, fontSize: 12)),
          const SizedBox(height: 14),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline_rounded, color: _cyan, size: 19), SizedBox(width: 9),
            Expanded(child: Text('La schermata successiva apre la sessione video solo quando avvii esplicitamente la telecamera o colleghi il monitor. Usa solo un server di segnalazione fidato.', style: TextStyle(color: _muted, height: 1.45, fontSize: 11))),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _role == _Role.camera ? CameraSenderScreen(remote: _remoteMode) : LocalViewerScreen(remote: _remoteMode))),
        icon: Icon(_role == _Role.camera ? Icons.videocam_rounded : Icons.tv_rounded),
        label: Text(_role == _Role.camera ? 'Configura trasmissione' : 'Configura ricezione video'),
        style: FilledButton.styleFrom(backgroundColor: _violet, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
      const SizedBox(height: 8),
      const Text('Questa schermata prepara il collegamento. Il monitor mostrerà i fotogrammi quando il relay avrà collegato entrambi i dispositivi.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11)),
    ]),
  );

  Widget _roleCard({required bool selected, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(duration: const Duration(milliseconds: 220), padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: selected ? _violet.withValues(alpha: .15) : _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? _violet : Colors.white.withValues(alpha: .06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: selected ? _cyan : _muted, size: 25), const SizedBox(height: 13),
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    ),
  );

  Widget _modeTile({required bool selected, required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: selected ? _panel2 : _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? _cyan.withValues(alpha: .55) : Colors.white.withValues(alpha: .05))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: selected ? _cyan : _muted, size: 23), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11, height: 1.4)),
        ])),
        if (selected) const Icon(Icons.check_circle_rounded, color: _cyan, size: 20),
      ]),
    ),
  );
}
