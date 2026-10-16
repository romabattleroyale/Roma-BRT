package com.sentinelone.nativeapp

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.util.Size
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.sceneview.SceneView
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberCameraManipulator
import io.github.sceneview.node.CubeNode
import io.github.sceneview.node.SphereNode
import io.github.sceneview.math.Position
import io.github.sceneview.math.Size as SceneSize
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private const val SERVICE_ID = "com.sentinelone.nativeapp.camera-link"
private const val PERMISSION_REQUEST = 401
private const val MAX_FRAME_BYTES = 28 * 1024

private val Night = Color(0xFF080B13)
private val Panel = Color(0xFF111827)
private val Cyan = Color(0xFF53E5F2)
private val Violet = Color(0xFF9A7BFF)
private val Muted = Color(0xFF9BA8BC)

class MainActivity : ComponentActivity() {
    private lateinit var connections: ConnectionsClient
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val captureActive = AtomicBoolean(false)
    private var imageCapture: ImageCapture? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var lensFacing by mutableIntStateOf(CameraSelector.LENS_FACING_BACK)
    private var role by mutableStateOf("monitor")
    private var status by mutableStateOf("Pronto per collegare i dispositivi")
    private var connectedName by mutableStateOf<String?>(null)
    private var discovered by mutableStateOf<List<Pair<String, String>>>(emptyList())
    private var working by mutableStateOf(false)
    private var remoteFrame by mutableStateOf<Bitmap?>(null)
    private var sentFrames by mutableIntStateOf(0)
    private var receivedFrames by mutableIntStateOf(0)
    private var activeEndpoint: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        connections = Nearby.getConnectionsClient(this)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Cyan, secondary = Violet, background = Night,
                    surface = Panel, onBackground = Color.White, onSurface = Color.White
                )
            ) {
                Dashboard(
                    role = role, status = status, connectedName = connectedName,
                    discovered = discovered, working = working, remoteFrame = remoteFrame,
                    sentFrames = sentFrames, receivedFrames = receivedFrames,
                    onRole = { role = it; stopSearching() },
                    onStart = { startPairing() },
                    onConnect = { endpoint -> requestPair(endpoint) },
                    onStop = { stopSearching() },
                    onSwitchCamera = { switchCamera() }
                )
            }
        }
    }

    private fun requiredPermissions(): Array<String> {
        val result = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            result += Manifest.permission.BLUETOOTH_SCAN
            result += Manifest.permission.BLUETOOTH_CONNECT
            result += Manifest.permission.BLUETOOTH_ADVERTISE
        } else {
            result += Manifest.permission.BLUETOOTH
            result += Manifest.permission.BLUETOOTH_ADMIN
            result += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= 33) result += Manifest.permission.NEARBY_WIFI_DEVICES
        if (role == "camera") result += Manifest.permission.CAMERA
        return result.toTypedArray()
    }

    private fun startPairing() {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST)
            status = "Concedi i permessi richiesti e premi di nuovo"
            return
        }
        discovered = emptyList()
        connectedName = null
        activeEndpoint = null
        working = true
        status = if (role == "monitor") "Monitor visibile agli altri telefoni" else "Ricerca del monitor nelle vicinanze…"
        if (role == "monitor") {
            connections.startAdvertising(
                "SENTINEL ONE · Monitor", SERVICE_ID, lifecycleCallback,
                AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build()
            ).addOnFailureListener { fail("Avvio monitor non riuscito: ${it.localizedMessage}") }
        } else {
            connections.startDiscovery(
                SERVICE_ID, discoveryCallback,
                DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build()
            ).addOnFailureListener { fail("Ricerca non riuscita: ${it.localizedMessage}") }
        }
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            runOnUiThread {
                if (discovered.none { it.first == endpointId }) {
                    discovered = discovered + (endpointId to info.endpointName)
                    status = "Monitor trovato: ${info.endpointName}"
                }
            }
        }
        override fun onEndpointLost(endpointId: String) {
            runOnUiThread { discovered = discovered.filterNot { it.first == endpointId } }
        }
    }

    private val lifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            connections.acceptConnection(endpointId, payloadCallback)
            runOnUiThread { status = "Conferma collegamento con ${info.endpointName}…" }
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            runOnUiThread {
                if (result.status.isSuccess) {
                    activeEndpoint = endpointId
                    connectedName = discovered.firstOrNull { it.first == endpointId }?.second ?: "SENTINEL ONE"
                    status = if (role == "camera") "Collegato · avvio fotocamera…" else "Collegato · in attesa del video"
                    working = false
                    connections.stopDiscovery()
                    connections.stopAdvertising()
                    if (role == "camera") startCameraCapture()
                } else {
                    status = "Collegamento non riuscito (codice ${result.status.statusCode})"
                    working = false
                }
            }
        }

        override fun onDisconnected(endpointId: String) {
            runOnUiThread {
                if (activeEndpoint == endpointId) activeEndpoint = null
                connectedName = null
                stopCameraCapture()
                status = "Dispositivo disconnesso"
                working = false
            }
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type != Payload.Type.BYTES) return
            val bytes = payload.asBytes() ?: return
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
            runOnUiThread {
                remoteFrame = bitmap
                receivedFrames += 1
                status = "Video in ricezione · frame $receivedFrames"
            }
        }
        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) = Unit
    }

    private fun startCameraCapture() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            status = "Permesso fotocamera mancante: autorizza e ricollega"
            return
        }
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                cameraProvider = provider
                val capture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setTargetResolution(Size(640, 480))
                    .build()
                provider.unbindAll()
                val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
                provider.bindToLifecycle(this, selector, capture)
                imageCapture = capture
                captureActive.set(true)
                status = "Fotocamera attiva · invio video"
                captureNextFrame()
            } catch (e: Exception) {
                fail("Fotocamera non avviata: ${e.localizedMessage}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun captureNextFrame() {
        if (!captureActive.get()) return
        val capture = imageCapture ?: return
        capture.takePicture(cameraExecutor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                try {
                    val buffer = image.planes.firstOrNull()?.buffer
                    if (buffer != null) {
                        val bytes = ByteArray(buffer.remaining())
                        buffer.get(bytes)
                        val compressed = compressForNearby(bytes)
                        val endpoint = activeEndpoint
                        if (compressed != null && endpoint != null && captureActive.get()) {
                            connections.sendPayload(endpoint, Payload.fromBytes(compressed))
                                .addOnSuccessListener { runOnUiThread { sentFrames += 1 } }
                                .addOnFailureListener { fail("Invio frame fallito: ${it.localizedMessage}") }
                        }
                    }
                } catch (e: Exception) {
                    fail("Errore frame: ${e.localizedMessage}")
                } finally {
                    image.close()
                    if (captureActive.get()) android.os.Handler(mainLooper).postDelayed({ captureNextFrame() }, 500L)
                }
            }

            override fun onError(exception: ImageCaptureException) {
                fail("Acquisizione frame fallita: ${exception.localizedMessage}")
                if (captureActive.get()) android.os.Handler(mainLooper).postDelayed({ captureNextFrame() }, 1000L)
            }
        })
    }

    private fun compressForNearby(source: ByteArray): ByteArray? {
        val bitmap = BitmapFactory.decodeByteArray(source, 0, source.size) ?: return null
        try {
            val scaled = Bitmap.createScaledBitmap(bitmap, 320, 240, true)
            try {
                var quality = 45
                var output: ByteArray
                do {
                    val stream = ByteArrayOutputStream()
                    scaled.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                    output = stream.toByteArray()
                    quality -= 5
                } while (output.size > MAX_FRAME_BYTES && quality >= 20)
                return output.takeIf { it.size <= MAX_FRAME_BYTES }
            } finally {
                if (scaled !== bitmap) scaled.recycle()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun switchCamera() {
        if (role != "camera" || activeEndpoint == null) {
            status = "Collega prima il monitor per cambiare fotocamera"
            return
        }
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        stopCameraCapture()
        status = if (lensFacing == CameraSelector.LENS_FACING_FRONT) "Passaggio alla fotocamera anteriore…" else "Passaggio alla fotocamera posteriore…"
        startCameraCapture()
    }

    private fun stopCameraCapture() {
        captureActive.set(false)
        imageCapture?.let { capture ->
            try { cameraProvider?.unbind(capture) } catch (_: Exception) { }
        }
        imageCapture = null
    }

    private fun requestPair(endpointId: String) {
        val name = discovered.firstOrNull { it.first == endpointId }?.second ?: "SENTINEL ONE"
        status = "Richiesta di collegamento a $name…"
        connections.requestConnection("SENTINEL ONE · Telecamera", endpointId, lifecycleCallback)
            .addOnFailureListener { fail("Richiesta fallita: ${it.localizedMessage}") }
    }

    private fun stopSearching() {
        if (!::connections.isInitialized) return
        stopCameraCapture()
        connections.stopDiscovery()
        connections.stopAdvertising()
        connections.stopAllEndpoints()
        activeEndpoint = null
        connectedName = null
        working = false
        status = "Ricerca interrotta"
    }

    private fun fail(message: String) {
        runOnUiThread { status = message; working = false }
    }

    override fun onDestroy() {
        stopCameraCapture()
        connections.stopAllEndpoints()
        cameraExecutor.shutdown()
        super.onDestroy()
    }
}

@Composable
private fun Dashboard(
    role: String,
    status: String,
    connectedName: String?,
    discovered: List<Pair<String, String>>,
    working: Boolean,
    remoteFrame: Bitmap?,
    sentFrames: Int,
    receivedFrames: Int,
    onRole: (String) -> Unit,
    onStart: () -> Unit,
    onConnect: (String) -> Unit,
    onStop: () -> Unit,
    onSwitchCamera: () -> Unit
) {
    var selectedTab by remember { mutableStateOf("Casa") }
    var selectedRoom by remember { mutableStateOf("Soggiorno") }
    var isDark by remember { mutableStateOf(true) }
    val background = if (isDark) Color(0xFF070B13) else Color(0xFFF2F5FA)
    val panel = if (isDark) Color(0xFF111827) else Color.White
    val primaryText = if (isDark) Color(0xFFF4F7FF) else Color(0xFF172033)
    val secondaryText = if (isDark) Color(0xFF9BA8BC) else Color(0xFF64718A)
    val accent = Color(0xFF56E6F2)
    val online = connectedName != null
    CompositionLocalProvider(LocalContentColor provides primaryText) {
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(if (isDark) Color(0xFF101A2B) else Color(0xFFE8F1FA), background, background)))) {
            Column(Modifier.fillMaxSize().statusBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(Modifier.size(46.dp).background(Brush.linearGradient(listOf(accent, Violet)), RoundedCornerShape(15.dp)), contentAlignment = Alignment.Center) {
                        Text("S", color = Color(0xFF07101A), fontSize = 26.sp, fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("SENTINEL ONE", fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.1.sp, color = primaryText)
                        Text("SMART HOME SECURITY", fontSize = 9.sp, color = secondaryText, letterSpacing = 1.8.sp)
                    }
                    Surface(onClick = { isDark = !isDark }, color = panel, shape = RoundedCornerShape(14.dp), border = androidx.compose.foundation.BorderStroke(1.dp, if (isDark) Color(0xFF283348) else Color(0xFFDDE5F0))) {
                        Text(if (isDark) "☼" else "☾", Modifier.padding(horizontal = 14.dp, vertical = 9.dp), fontSize = 19.sp, color = accent)
                    }
                }

                Column(
                    Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(0.dp)
                ) {
                    when (selectedTab) {
                        "Casa" -> {
                            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text("La tua casa", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                        Text("Tutto sotto controllo.", fontSize = 14.sp, color = secondaryText)
                                    }
                                    Surface(color = if (online) Color(0xFF153A36) else panel, shape = RoundedCornerShape(50), border = androidx.compose.foundation.BorderStroke(1.dp, if (online) Color(0xFF287D73) else Color(0xFF2A3448))) {
                                        Row(Modifier.padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Box(Modifier.size(7.dp).background(if (online) Color(0xFF55E6B1) else Violet, RoundedCornerShape(50)))
                                            Text(if (online) "PROTETTA" else "PRONTA", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = if (online) Color(0xFF55E6B1) else secondaryText)
                                        }
                                    }
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                                    MetricTile("TELECAMERE", if (online) "1" else "0", if (online) "1 collegata" else "In attesa", panel, primaryText, secondaryText, accent, Modifier.weight(1f))
                                    MetricTile("STATO CASA", if (online) "LIVE" else "OK", if (online) "Flusso attivo" else "Nessun allarme", panel, primaryText, secondaryText, Violet, Modifier.weight(1f))
                                    MetricTile("EVENTI", "0", "Oggi", panel, primaryText, secondaryText, Color(0xFFFFB86B), Modifier.weight(1f))
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text("MODELLO 3D", fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = secondaryText)
                                        Text("Vista della casa", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = primaryText)
                                    }
                                    Text("TRASCINA PER RUOTARE", fontSize = 8.sp, color = secondaryText, letterSpacing = 0.7.sp)
                                }
                                HouseModel3D(panel = panel, accent = accent, selectedRoom = selectedRoom, onRoomSelected = { selectedRoom = it }, isDark = isDark)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    listOf("Soggiorno", "Cucina", "Camera").forEach { room ->
                                        val chosen = selectedRoom == room
                                        Surface(onClick = { selectedRoom = room }, color = if (chosen) Color(0xFF17343E) else panel, shape = RoundedCornerShape(12.dp), border = androidx.compose.foundation.BorderStroke(1.dp, if (chosen) accent else Color.Transparent)) {
                                            Text(room, Modifier.padding(horizontal = 12.dp, vertical = 9.dp), color = if (chosen) accent else secondaryText, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                                        }
                                    }
                                }
                                Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(20.dp), border = androidx.compose.foundation.BorderStroke(1.dp, if (isDark) Color(0xFF202B3D) else Color(0xFFE1E8F1))) {
                                    Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Box(Modifier.size(42.dp).background(Color(0xFF18343B), RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) { Text("⌁", fontSize = 22.sp, color = accent) }
                                        Column(Modifier.weight(1f)) {
                                            Text("Telecamere e copertura", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = primaryText)
                                            Text(if (online) "Dispositivo collegato: $connectedName" else "Collega un dispositivo per iniziare il monitoraggio", fontSize = 11.sp, color = secondaryText)
                                        }
                                        Text("›", color = accent, fontSize = 26.sp)
                                    }
                                }
                            }
                        }
                        "Live" -> {
                            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Text("Video live", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                Text("Flussi delle tue telecamere", fontSize = 14.sp, color = secondaryText)
                                if (remoteFrame != null) {
                                    Card(colors = CardDefaults.cardColors(containerColor = Color.Black), shape = RoundedCornerShape(22.dp)) {
                                        Column {
                                            Image(bitmap = remoteFrame.asImageBitmap(), contentDescription = "Video live dalla telecamera", modifier = Modifier.fillMaxWidth().heightIn(min = 220.dp, max = 390.dp))
                                            Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                                Box(Modifier.size(7.dp).background(Color(0xFFFF5964), RoundedCornerShape(50)))
                                                Spacer(Modifier.width(8.dp))
                                                Text("LIVE", color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                                Spacer(Modifier.weight(1f))
                                                Text("$receivedFrames frame ricevuti", color = Color.LightGray, fontSize = 10.sp)
                                            }
                                        }
                                    }
                                } else {
                                    EmptyStateCard("Nessun flusso attivo", "Quando una telecamera si collega, il video comparirà qui.", panel, primaryText, secondaryText, accent)
                                }
                                if (role == "camera" && connectedName != null) {
                                    OutlinedButton(onClick = onSwitchCamera, modifier = Modifier.fillMaxWidth()) { Text("Cambia fotocamera") }
                                }
                                Text("CONNESSIONE", fontSize = 10.sp, letterSpacing = 1.4.sp, color = secondaryText)
                                Text(status, fontSize = 12.sp, color = secondaryText)
                            }
                        }
                        "Eventi" -> {
                            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Text("Eventi e attività", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                Text("Cronologia di sicurezza", fontSize = 14.sp, color = secondaryText)
                                EmptyStateCard("Nessun evento registrato", "Gli eventi appariranno qui quando sarà implementato e attivato il rilevamento.", panel, primaryText, secondaryText, Color(0xFFFFB86B))
                                Text("STATO ATTUALE", fontSize = 10.sp, color = secondaryText, letterSpacing = 1.4.sp)
                                Text(status, fontSize = 12.sp, color = secondaryText)
                            }
                        }
                        "Dispositivi" -> {
                            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(13.dp)) {
                                Text("Dispositivi", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                Text("Aggiungi una telecamera o un monitor Android", fontSize = 13.sp, color = secondaryText)
                                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                                    RoleCard("TELECAMERA", "Invia il video", role == "camera", Modifier.weight(1f).height(90.dp)) { onRole("camera") }
                                    RoleCard("MONITOR", "Riceve il video", role == "monitor", Modifier.weight(1f).height(90.dp)) { onRole("monitor") }
                                }
                                Button(onClick = onStart, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(15.dp), colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color(0xFF07101A))) {
                                    Text(if (working) "RICERCA IN CORSO…" else if (role == "monitor") "RENDi VISIBILE IL MONITOR" else "CERCA DISPOSITIVI", fontWeight = FontWeight.Bold)
                                }
                                if (working || connectedName != null) OutlinedButton(onClick = onStop, modifier = Modifier.fillMaxWidth()) { Text("Interrompi / scollega") }
                                Text("STATO", fontSize = 10.sp, color = secondaryText, letterSpacing = 1.4.sp)
                                Text(status, fontSize = 12.sp, color = secondaryText)
                                if (discovered.isNotEmpty()) {
                                    discovered.forEach { item ->
                                        Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(16.dp)) {
                                            Row(Modifier.fillMaxWidth().padding(13.dp), verticalAlignment = Alignment.CenterVertically) {
                                                Column(Modifier.weight(1f)) {
                                                    Text(item.second, color = primaryText, fontWeight = FontWeight.Bold)
                                                    Text("Dispositivo nelle vicinanze", color = secondaryText, fontSize = 11.sp)
                                                }
                                                Button(onClick = { onConnect(item.first) }) { Text("Collega") }
                                            }
                                        }
                                    }
                                }
                                if (connectedName != null) EmptyStateCard("Collegato", connectedName, panel, primaryText, secondaryText, Color(0xFF55E6B1))
                            }
                        }
                        else -> {
                            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Text("Impostazioni", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                Text("Personalizza la tua centrale di sicurezza", fontSize = 13.sp, color = secondaryText)
                                Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(18.dp)) {
                                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Text("Aspetto", fontWeight = FontWeight.Bold, color = primaryText)
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(if (isDark) "Tema scuro" else "Tema chiaro", Modifier.weight(1f), color = secondaryText)
                                            Switch(checked = isDark, onCheckedChange = { isDark = it })
                                        }
                                        HorizontalDivider(color = secondaryText.copy(alpha = 0.2f))
                                        Text("SENTINEL ONE · NATIVE", fontSize = 10.sp, letterSpacing = 1.2.sp, color = secondaryText)
                                        Text("Prototipo in sviluppo. Le integrazioni di terze parti e le funzioni di registrazione/eventi richiedono implementazione e test dedicati.", fontSize = 12.sp, color = secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }

                NavigationBar(containerColor = panel, contentColor = primaryText, tonalElevation = 0.dp) {
                    listOf("Casa" to "⌂", "Live" to "◉", "Eventi" to "◷", "Dispositivi" to "▣", "Impostazioni" to "⚙").forEach { item ->
                        NavigationBarItem(
                            selected = selectedTab == item.first,
                            onClick = { selectedTab = item.first },
                            icon = { Text(item.second, fontSize = 19.sp, color = if (selectedTab == item.first) accent else secondaryText) },
                            label = { Text(item.first, fontSize = 9.sp, maxLines = 1) },
                            colors = NavigationBarItemDefaults.colors(selectedIconColor = accent, selectedTextColor = accent, indicatorColor = if (isDark) Color(0xFF17343E) else Color(0xFFDDF8FA), unselectedIconColor = secondaryText, unselectedTextColor = secondaryText)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricTile(title: String, value: String, caption: String, panel: Color, primary: Color, secondary: Color, accent: Color, modifier: Modifier = Modifier) {
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(16.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.18f))) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(title, fontSize = 8.sp, color = secondary, letterSpacing = 0.5.sp, maxLines = 1)
            Text(value, fontSize = 20.sp, color = accent, fontWeight = FontWeight.ExtraBold)
            Text(caption, fontSize = 8.sp, color = secondary, maxLines = 1)
        }
    }
}

@Composable
private fun EmptyStateCard(title: String, subtitle: String, panel: Color, primary: Color, secondary: Color, accent: Color) {
    Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(20.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.22f))) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.Start) {
            Box(Modifier.size(42.dp).background(accent.copy(alpha = 0.12f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                Text("◎", color = accent, fontSize = 23.sp)
            }
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = primary)
            Text(subtitle, fontSize = 12.sp, color = secondary)
        }
    }
}

@Composable
private fun HouseModel3D(panel: Color, accent: Color, selectedRoom: String, onRoomSelected: (String) -> Unit, isDark: Boolean) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val wall = if (isDark) Color(0xFF61738B) else Color(0xFF9DAFC2)
    val floor = if (isDark) Color(0xFF253448) else Color(0xFFD7E1EB)
    val onlineGreen = Color(0xFF35E59A)
    val offlineRed = Color(0xFFFF5964)
    var basement by remember { mutableStateOf(false) }
    var cameras by remember { mutableStateOf(true) }
    Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(24.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.22f))) {
        Column(Modifier.fillMaxWidth().padding(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (basement) "CASA · SEMINTERRATO" else "CASA · PIANO PRINCIPALE", color = if (isDark) Color(0xFFB5C5D8) else Color(0xFF53647B), fontSize = 9.sp, letterSpacing = 1.sp)
                    Text("SCENA 3D · FILAMENT", color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
                Surface(color = Color(0xFF12372D), shape = RoundedCornerShape(50)) {
                    Text("● ONLINE", Modifier.padding(horizontal = 9.dp, vertical = 6.dp), color = onlineGreen, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                }
            }
            Box(Modifier.fillMaxWidth().height(290.dp).padding(top = 8.dp).background(if (isDark) Color(0xFF090F19) else Color(0xFFEAF0F6), RoundedCornerShape(18.dp))) {
                SceneView(
                    modifier = Modifier.fillMaxSize(),
                    engine = engine,
                    modelLoader = modelLoader,
                    cameraManipulator = rememberCameraManipulator()
                ) {
                    CubeNode(size = SceneSize(4.2f), position = Position(y = -0.14f), color = floor)
                    CubeNode(size = SceneSize(0.12f), position = Position(x = -1.8f, y = 0.55f), color = wall)
                    CubeNode(size = SceneSize(0.12f), position = Position(x = 1.8f, y = 0.55f), color = wall)
                    CubeNode(size = SceneSize(0.12f), position = Position(y = 0.55f, z = -1.8f), color = wall)
                    CubeNode(size = SceneSize(0.12f), position = Position(y = 0.55f, z = 1.8f), color = wall)
                    CubeNode(size = SceneSize(0.10f), position = Position(x = -0.55f, y = 0.55f), color = wall)
                    CubeNode(size = SceneSize(0.10f), position = Position(x = 0.65f, y = 0.55f, z = -0.35f), color = wall)
                    CubeNode(size = SceneSize(0.48f), position = Position(x = -1.0f, y = 0.12f, z = -0.75f), color = if (selectedRoom == "Soggiorno") accent else wall)
                    CubeNode(size = SceneSize(0.34f), position = Position(x = 1.0f, y = 0.10f, z = -0.7f), color = if (selectedRoom == "Cucina") accent else wall)
                    CubeNode(size = SceneSize(0.40f), position = Position(x = 1.0f, y = 0.12f, z = 0.95f), color = if (selectedRoom == "Camera") accent else wall)
                    if (cameras) {
                        SphereNode(radius = 0.10f, position = Position(x = -1.6f, y = 1.05f, z = -1.55f), color = offlineRed)
                        SphereNode(radius = 0.10f, position = Position(x = 1.55f, y = 1.05f, z = -1.55f), color = offlineRed)
                        SphereNode(radius = 0.10f, position = Position(x = 1.55f, y = 1.05f, z = 1.55f), color = offlineRed)
                    }
                    if (basement) {
                        CubeNode(size = SceneSize(3.2f), position = Position(y = -1.15f), color = if (isDark) Color(0xFF182333) else Color(0xFFCAD5E1))
                        CubeNode(size = SceneSize(0.10f), position = Position(y = -0.72f, z = -1.35f), color = wall)
                        CubeNode(size = SceneSize(0.10f), position = Position(x = -1.35f, y = -0.72f), color = wall)
                        SphereNode(radius = 0.09f, position = Position(x = -1.2f, y = -0.55f, z = -1.2f), color = offlineRed)
                    }
                }
            }
            Text("Scena 3D renderizzata da Filament · trascina per orbitare", Modifier.padding(top = 6.dp), color = if (isDark) Color(0xFF8292A9) else Color(0xFF65758A), fontSize = 9.sp)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                listOf("Soggiorno", "Cucina", "Camera").forEach { room ->
                    val selected = selectedRoom == room
                    Surface(onClick = { onRoomSelected(room) }, color = if (selected) Color(0xFF17343E) else if (isDark) Color(0xFF172131) else Color(0xFFE8EEF5), shape = RoundedCornerShape(11.dp), border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) accent else Color.Transparent)) {
                        Text(room, Modifier.padding(horizontal = 9.dp, vertical = 8.dp), color = if (selected) accent else if (isDark) Color(0xFFB5C5D8) else Color(0xFF53647B), fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { basement = !basement }) { Text(if (basement) "Piano principale" else "Seminterrato") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { cameras = !cameras }) { Text(if (cameras) "Nascondi telecamere" else "Mostra telecamere") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).background(onlineGreen, RoundedCornerShape(50))); Spacer(Modifier.width(5.dp)); Text("Online", color = if (isDark) Color(0xFFB5C5D8) else Color(0xFF53647B), fontSize = 10.sp) }
                Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(8.dp).background(offlineRed, RoundedCornerShape(50))); Spacer(Modifier.width(5.dp)); Text("Offline / non collegata", color = if (isDark) Color(0xFFB5C5D8) else Color(0xFF53647B), fontSize = 10.sp) }
            }
        }
    }
}

@Composable
private fun RoleCard(title: String, subtitle: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick, modifier = modifier.height(82.dp),
        color = if (selected) Color(0xFF17323A) else Color(0xFF0B111C),
        shape = RoundedCornerShape(16.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) Cyan else Color(0xFF283348))
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.Center) {
            Text(title, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (selected) Cyan else Color.White)
            Spacer(Modifier.height(5.dp))
            Text(subtitle, fontSize = 11.sp, color = Muted)
        }
    }
}
