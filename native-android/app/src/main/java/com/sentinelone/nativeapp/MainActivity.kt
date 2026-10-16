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
                            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
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
                            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
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
    var rotation by remember { mutableFloatStateOf(0f) }
    val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "houseGlow")
    val pulse by transition.animateFloat(initialValue = 0.45f, targetValue = 0.95f, animationSpec = androidx.compose.animation.core.infiniteRepeatable(animation = androidx.compose.animation.core.tween(1400), repeatMode = androidx.compose.animation.core.RepeatMode.Reverse), label = "cameraPulse")
    val wallFront = if (isDark) Color(0xFF26364B) else Color(0xFFD3DEEA)
    val wallSide = if (isDark) Color(0xFF1B283A) else Color(0xFFBBCBDB)
    val floorColor = if (isDark) Color(0xFF172638) else Color(0xFFE5EDF5)
    Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(24.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.22f))) {
        Column(Modifier.fillMaxWidth().padding(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("CASA · PIANO PRINCIPALE", Modifier.weight(1f), color = if (isDark) Color(0xFFB5C5D8) else Color(0xFF53647B), fontSize = 9.sp, letterSpacing = 1.sp)
                Text("3D PREVIEW", color = accent, fontSize = 9.sp, fontWeight = FontWeight.Bold)
            }
            androidx.compose.foundation.Canvas(
                modifier = Modifier.fillMaxWidth().height(218.dp)
                    .pointerInput(Unit) {
                        androidx.compose.foundation.gestures.detectDragGestures { change, dragAmount ->
                            change.consume()
                            rotation += dragAmount.x * 0.012f
                        }
                    }
            ) {
                val w = size.width
                val h = size.height
                val cx = w * 0.50f + kotlin.math.sin(rotation) * w * 0.035f
                val top = h * 0.12f
                val left = cx - w * 0.28f
                val right = cx + w * 0.27f
                val midX = cx + w * 0.015f
                val yTop = top + kotlin.math.cos(rotation) * 4f
                val yMid = h * 0.49f
                val yBottom = h * 0.83f
                val depth = w * 0.17f
                val pFloor = androidx.compose.ui.graphics.Path().apply {
                    moveTo(left, yMid); lineTo(midX, yMid - depth * 0.42f); lineTo(right, yMid); lineTo(midX, yBottom); close()
                }
                drawPath(pFloor, floorColor)
                val frontWall = androidx.compose.ui.graphics.Path().apply {
                    moveTo(left, yMid); lineTo(midX, yMid - depth * 0.42f); lineTo(midX, yTop); lineTo(left, yTop + depth * 0.48f); close()
                }
                val sideWall = androidx.compose.ui.graphics.Path().apply {
                    moveTo(midX, yMid - depth * 0.42f); lineTo(right, yMid); lineTo(right, yTop + depth * 0.48f); lineTo(midX, yTop); close()
                }
                drawPath(frontWall, wallFront)
                drawPath(sideWall, wallSide)
                val roof = androidx.compose.ui.graphics.Path().apply {
                    moveTo(left - 8f, yTop + depth * 0.48f); lineTo(midX, yTop - depth * 0.30f); lineTo(right + 8f, yTop + depth * 0.48f); lineTo(midX, yMid - depth * 0.42f); close()
                }
                drawPath(roof, if (isDark) Color(0xFF31465F) else Color(0xFFB5C6D8))
                // Front wall room divisions and luminous windows
                val wallLine = if (isDark) Color(0xFF60758E) else Color(0xFF8EA3B8)
                drawLine(wallLine, Offset(left, yTop + depth * 0.48f), Offset(left, yMid), 2f)
                drawLine(wallLine, Offset(left, yMid), Offset(midX, yMid - depth * 0.42f), 2f)
                drawLine(wallLine, Offset(midX, yMid - depth * 0.42f), Offset(midX, yTop), 2f)
                drawLine(wallLine, Offset(midX, yTop), Offset(left, yTop + depth * 0.48f), 2f)
                drawLine(wallLine, Offset(midX, yTop), Offset(right, yTop + depth * 0.48f), 2f)
                drawLine(wallLine, Offset(midX, yMid - depth * 0.42f), Offset(right, yMid), 2f)
                drawLine(wallLine, Offset(right, yTop + depth * 0.48f), Offset(right, yMid), 2f)
                val windowGlow = accent.copy(alpha = pulse)
                drawRoundRect(windowGlow, Offset(left + 18f, yTop + 29f), Size(20f, 27f), androidx.compose.ui.geometry.CornerRadius(4f))
                drawRoundRect(windowGlow.copy(alpha = pulse * 0.65f), Offset(midX + 19f, yTop + 29f), Size(20f, 27f), androidx.compose.ui.geometry.CornerRadius(4f))
                drawRoundRect(if (selectedRoom == "Soggiorno") accent.copy(alpha = 0.30f) else wallLine.copy(alpha = 0.45f), Offset(left + 12f, yMid + 14f), Size(w * 0.12f, h * 0.12f), androidx.compose.ui.geometry.CornerRadius(5f))
                drawRoundRect(if (selectedRoom == "Cucina") accent.copy(alpha = 0.35f) else wallLine.copy(alpha = 0.45f), Offset(midX + 13f, yMid + 9f), Size(w * 0.11f, h * 0.12f), androidx.compose.ui.geometry.CornerRadius(5f))
                // Camera markers with soft glow
                val cam1 = Offset(left + w * 0.10f, yTop + 17f)
                val cam2 = Offset(right - w * 0.06f, yTop + 23f)
                drawCircle(accent.copy(alpha = 0.14f), 15f, cam1)
                drawCircle(accent.copy(alpha = pulse), 5f, cam1)
                drawCircle(Violet.copy(alpha = 0.18f), 15f, cam2)
                drawCircle(Violet.copy(alpha = pulse), 5f, cam2)
                // Ground shadow and orientation cue
                drawLine(accent.copy(alpha = 0.30f), Offset(left - 12f, yBottom + 7f), Offset(right + 14f, yBottom + 7f), 1.5f)
            }
            Text("Modello dimostrativo · trascina per ruotare", Modifier.padding(top = 3.dp), color = if (isDark) Color(0xFF8292A9) else Color(0xFF65758A), fontSize = 9.sp)
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
