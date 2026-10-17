package com.sentinelone.nativeapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Build
import android.os.Bundle
import android.util.Size
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.compose.foundation.Image
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.animation.animateContentSize
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
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
private const val MAX_FRAME_BYTES = 120 * 1024

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
    private var imageAnalysis: ImageAnalysis? = null
    private val frameInFlight = AtomicBoolean(false)
    private var cameraProvider: ProcessCameraProvider? = null
    private var lensFacing by mutableIntStateOf(CameraSelector.LENS_FACING_BACK)
    private var role by mutableStateOf("monitor")
    private var hasChosenMode by mutableStateOf(false)
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
                if (!hasChosenMode) {
                    WelcomeScreen(
                        onCameraMode = {
                            role = "camera"
                            hasChosenMode = true
                            startPairing()
                        },
                        onControlMode = {
                            role = "monitor"
                            hasChosenMode = true
                            startPairing()
                        }
                    )
                } else {
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
        }
        // Nearby Connections discovery on this device reports missing coarse location,
        // so request it on all Android versions; fine location is also declared for compatibility.
        result += Manifest.permission.ACCESS_COARSE_LOCATION
        result += Manifest.permission.ACCESS_FINE_LOCATION
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
        remoteFrame = null
        sentFrames = 0
        receivedFrames = 0
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
            // Only render frames from the endpoint that completed the connection.
            if (endpointId != activeEndpoint || payload.type != Payload.Type.BYTES) return
            val bytes = payload.asBytes() ?: return
            if (bytes.isEmpty() || bytes.size > MAX_FRAME_BYTES) return
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
            runOnUiThread {
                if (endpointId != activeEndpoint) {
                    bitmap.recycle()
                    return@runOnUiThread
                }
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
                val analysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(640, 480))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(cameraExecutor) { proxy ->
                    try {
                        if (captureActive.get() && !frameInFlight.get()) {
                            val jpeg = imageProxyToJpeg(proxy)
                            val endpoint = activeEndpoint
                            if (jpeg != null && endpoint != null && frameInFlight.compareAndSet(false, true)) {
                                connections.sendPayload(endpoint, Payload.fromBytes(jpeg))
                                    .addOnFailureListener { fail("Invio frame fallito: ${it.localizedMessage}") }
                                    .addOnCompleteListener { frameInFlight.set(false) }
                                runOnUiThread { sentFrames += 1 }
                            }
                        }
                    } catch (e: Exception) {
                        fail("Errore elaborazione video: ${e.localizedMessage}")
                    } finally {
                        proxy.close()
                    }
                }
                provider.unbindAll()
                val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
                provider.bindToLifecycle(this, selector, analysis)
                imageAnalysis = analysis
                captureActive.set(true)
                status = "Fotocamera attiva · streaming live"
            } catch (e: Exception) {
                fail("Fotocamera non avviata: ${e.localizedMessage}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun captureNextFrame() {
        if (!captureActive.get()) return
        val capture = imageCapture ?: return
        val frameFile = java.io.File(cacheDir, "sentinel_frame_${System.nanoTime()}.jpg")
        val output = ImageCapture.OutputFileOptions.Builder(frameFile).build()
        capture.takePicture(output, cameraExecutor, object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                try {
                    val source = frameFile.readBytes()
                    val compressed = compressForNearby(source)
                    val endpoint = activeEndpoint
                    if (compressed != null && endpoint != null && captureActive.get()) {
                        connections.sendPayload(endpoint, Payload.fromBytes(compressed))
                            .addOnSuccessListener { runOnUiThread { sentFrames += 1 } }
                            .addOnFailureListener { fail("Invio frame fallito: ${it.localizedMessage}") }
                    }
                } catch (e: Exception) {
                    fail("Errore frame: ${e.localizedMessage}")
                } finally {
                    frameFile.delete()
                    if (captureActive.get()) android.os.Handler(mainLooper).postDelayed({ captureNextFrame() }, 180L)
                }
            }

            override fun onError(exception: ImageCaptureException) {
                frameFile.delete()
                fail("Acquisizione frame fallita: ${exception.localizedMessage}")
                if (captureActive.get()) android.os.Handler(mainLooper).postDelayed({ captureNextFrame() }, 1000L)
            }
        })
    }

    private fun imageProxyToJpeg(proxy: ImageProxy): ByteArray? {
        if (proxy.format != ImageFormat.YUV_420_888) return null
        val y = proxy.planes[0].buffer
        val u = proxy.planes[1].buffer
        val v = proxy.planes[2].buffer
        val width = proxy.width
        val height = proxy.height
        val nv21 = ByteArray(width * height * 3 / 2)
        var offset = 0
        val yRowStride = proxy.planes[0].rowStride
        val yPixelStride = proxy.planes[0].pixelStride
        for (row in 0 until height) {
            for (col in 0 until width) nv21[offset++] = y.get(row * yRowStride + col * yPixelStride)
        }
        val uRowStride = proxy.planes[1].rowStride
        val uPixelStride = proxy.planes[1].pixelStride
        val vRowStride = proxy.planes[2].rowStride
        val vPixelStride = proxy.planes[2].pixelStride
        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {
                nv21[offset++] = v.get(row * vRowStride + col * vPixelStride)
                nv21[offset++] = u.get(row * uRowStride + col * uPixelStride)
            }
        }
        val output = ByteArrayOutputStream()
        val image = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        if (!image.compressToJpeg(Rect(0, 0, width, height), 68, output)) return null
        val bytes = output.toByteArray()
        return bytes.takeIf { it.size <= 120 * 1024 }
    }

    private fun compressForNearby(source: ByteArray): ByteArray? {
        val bitmap = BitmapFactory.decodeByteArray(source, 0, source.size) ?: return null
        try {
            val scaled = Bitmap.createScaledBitmap(bitmap, 320, 240, true)
            try {
                var quality = 38
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
        imageAnalysis?.clearAnalyzer()
        imageAnalysis?.let { analysis -> try { cameraProvider?.unbind(analysis) } catch (_: Exception) { } }
        imageAnalysis = null
        frameInFlight.set(false)
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
        remoteFrame = null
        sentFrames = 0
        receivedFrames = 0
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
private fun WelcomeScreen(onCameraMode: () -> Unit, onControlMode: () -> Unit) {
    val muted = Color(0xFF9BA8BC)
    Box(Modifier.fillMaxSize().background(Color(0xFF080B13))) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Spacer(Modifier.height(14.dp))
            SentinelLogo(Modifier.size(64.dp))
            Text("SENTINEL ONE", color = Color(0xFFF4F7FF), fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = 0.6.sp)
            Text("VIDEOSORVEGLIANZA SEMPLICE", color = muted, fontSize = 10.sp, letterSpacing = 1.8.sp)
            Spacer(Modifier.height(20.dp))
            Text("Da quale telefono\nvuoi iniziare?", color = Color.White, fontSize = 29.sp, lineHeight = 34.sp, fontWeight = FontWeight.ExtraBold)
            Text("Usa due telefoni Android. Uno riprende, l'altro mostra il video in diretta.", color = muted, fontSize = 14.sp, lineHeight = 21.sp)
            Spacer(Modifier.height(10.dp))
            ModeChoiceCard("TELEFONO 1", "Telecamera", "Questo telefono invia il video della fotocamera.", "USA COME TELECAMERA", "◉", Color(0xFF53E5F2), onCameraMode)
            ModeChoiceCard("TELEFONO 2", "Centro di controllo", "Questo telefono cerca la telecamera e mostra il live.", "USA COME MONITOR", "⌂", Color(0xFF53E5F2), onControlMode)
            Spacer(Modifier.height(8.dp))
            Surface(color = Color(0xFF111827), shape = RoundedCornerShape(16.dp)) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("i", color = Color(0xFF53E5F2), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    Text("Tieni entrambi i telefoni vicini, con Bluetooth attivo e permessi richiesti concessi. Avvia prima il Centro di controllo sul telefono che riceve.", color = muted, fontSize = 12.sp, lineHeight = 18.sp)
                }
            }
        }
    }
}

@Composable
private fun SentinelLogo(modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
            val shield = androidx.compose.ui.graphics.Path().apply {
                moveTo(size.width * 0.5f, size.height * 0.04f)
                lineTo(size.width * 0.9f, size.height * 0.2f)
                lineTo(size.width * 0.85f, size.height * 0.58f)
                quadraticTo(size.width * 0.79f, size.height * 0.82f, size.width * 0.5f, size.height * 0.96f)
                quadraticTo(size.width * 0.21f, size.height * 0.82f, size.width * 0.15f, size.height * 0.58f)
                lineTo(size.width * 0.1f, size.height * 0.2f)
                close()
            }
            drawPath(shield, Brush.linearGradient(listOf(Color(0xFF38E4F4), Color(0xFF786BFF), Color(0xFFB06DFF))))
        }
        Text("S", color = Color(0xFF07101A), fontSize = 43.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun ModeChoiceCard(
    title: String, emphasis: String, description: String, action: String,
    symbol: String, accent: Color, onClick: () -> Unit
) {
    var pressed by remember { mutableStateOf(false) }
    val scale by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (pressed) 0.985f else 1f,
        animationSpec = androidx.compose.animation.core.spring(dampingRatio = 0.55f, stiffness = 500f),
        label = "mode-card-scale"
    )
    Card(
        onClick = { pressed = true; onClick() },
        modifier = Modifier.fillMaxWidth().heightIn(min = 142.dp).graphicsLayer { scaleX = scale; scaleY = scale }.animateContentSize(),
        shape = RoundedCornerShape(25.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF111C2D)),
        border = androidx.compose.foundation.BorderStroke(1.3.dp, accent.copy(alpha = 0.8f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 5.dp, pressedElevation = 12.dp)
    ) {
        Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(58.dp).background(Brush.linearGradient(listOf(accent.copy(alpha = 0.22f), Color(0xFF101827))), RoundedCornerShape(17.dp)), contentAlignment = Alignment.Center) {
                    Text(symbol, color = accent, fontSize = 36.sp, fontWeight = FontWeight.Light)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(title, color = Color(0xFFF4F7FF), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp)
                    Text(emphasis, color = accent, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
                    Text(description, color = Color(0xFFB1BED1), fontSize = 12.sp, lineHeight = 17.sp)
                }
            }
            Surface(color = accent, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(action, color = Color(0xFF07101A), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f))
                    Text("→", color = Color(0xFF07101A), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}


@Composable
private fun ModeHeroCard(title: String, subtitle: String, accent: Color, symbol: String, connected: Boolean) {
    Card(
        modifier = Modifier.fillMaxWidth().heightIn(min = 150.dp),
        shape = RoundedCornerShape(25.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF111C2D)),
        border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.55f))
    ) {
        Box(Modifier.fillMaxWidth().background(Brush.horizontalGradient(listOf(accent.copy(alpha = 0.16f), Color(0xFF111C2D))))) {
            Row(Modifier.fillMaxWidth().padding(19.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(15.dp)) {
                Box(Modifier.size(82.dp).background(Brush.linearGradient(listOf(accent.copy(alpha = 0.3f), Color(0xFF0A1220))), RoundedCornerShape(24.dp)), contentAlignment = Alignment.Center) {
                    Text(symbol, color = accent, fontSize = 50.sp, fontWeight = FontWeight.Light)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Text(title, color = accent, fontSize = 11.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.3.sp)
                    Text(subtitle, color = Color(0xFFF4F7FF), fontSize = 16.sp, fontWeight = FontWeight.Bold, lineHeight = 21.sp)
                    Text(if (connected) "● CONNESSO" else "● CONNESSIONE SICURA", color = if (connected) Color(0xFF55E6B1) else Color(0xFF9BAAC0), fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.7.sp)
                }
            }
        }
    }
}

@Composable
private fun PairingInstruction(number: String, instruction: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(24.dp).background(Color(0xFF17343E), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
            Text(number, color = Color(0xFF53E5F2), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
        }
        Text(instruction, color = Color(0xFFCFD8E6), fontSize = 12.sp, lineHeight = 18.sp, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun ModeMiniCard(title: String, subtitle: String, selected: Boolean, accent: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val scale by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (selected) 1f else 0.985f,
        animationSpec = androidx.compose.animation.core.spring(dampingRatio = 0.7f, stiffness = 450f),
        label = "mode-mini-scale"
    )
    Card(
        onClick = onClick,
        modifier = modifier.height(88.dp).graphicsLayer { scaleX = scale; scaleY = scale },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = if (selected) accent.copy(alpha = 0.13f) else Color(0xFF111827)),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) accent else Color(0xFF283348))
    ) {
        Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.Center) {
            Text(title, color = if (selected) accent else Color(0xFFF4F7FF), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
            Spacer(Modifier.height(5.dp))
            Text(subtitle, color = Color(0xFF9BAAC0), fontSize = 10.sp)
        }
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
    val context = androidx.compose.ui.platform.LocalContext.current
    var selectedTab by remember { mutableStateOf("Casa") }
    var isDark by remember { mutableStateOf(true) }
    val background = if (isDark) Color(0xFF070B13) else Color(0xFFF2F5FA)
    val panel = if (isDark) Color(0xFF111827) else Color.White
    val primaryText = if (isDark) Color(0xFFF4F7FF) else Color(0xFF172033)
    val secondaryText = if (isDark) Color(0xFF9BA8BC) else Color(0xFF64718A)
    val accent = Color(0xFF56E6F2)
    val online = connectedName != null
    CompositionLocalProvider(LocalContentColor provides primaryText) {
        Box(Modifier.fillMaxSize().background(background)) {
            Column(Modifier.fillMaxSize().statusBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SentinelLogo(Modifier.size(48.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("SENTINEL ONE", fontSize = 16.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.1.sp, color = primaryText)
                        Text("SMART HOME SECURITY", fontSize = 9.sp, color = secondaryText, letterSpacing = 1.8.sp)
                    }
                    Surface(
                        onClick = { isDark = !isDark },
                        color = panel,
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.dp, if (isDark) Color(0xFF283348) else Color(0xFFDDE5F0))
                    ) {
                        Text(if (isDark) "☼" else "☾", Modifier.padding(horizontal = 13.dp, vertical = 9.dp), fontSize = 19.sp, color = accent)
                    }
                }
                when (selectedTab) {
                    "Casa" -> {
                        Column(
                            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("La tua sicurezza", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                                    Text("Tutto sotto controllo.", fontSize = 14.sp, color = secondaryText)
                                }
                                Surface(
                                    color = if (online) Color(0xFF12352F) else panel,
                                    shape = RoundedCornerShape(50),
                                    border = androidx.compose.foundation.BorderStroke(1.dp, if (online) Color(0xFF2C8A78) else Color(0xFF2A3448))
                                ) {
                                    Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Box(Modifier.size(7.dp).background(if (online) Color(0xFF55E6B1) else Color(0xFFFFC36B), RoundedCornerShape(50)))
                                        Text(if (online) "COLLEGATA" else "IN ATTESA", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = if (online) Color(0xFF55E6B1) else secondaryText)
                                    }
                                }
                            }

                            SecurityHeroVisual(
                                isDark = isDark,
                                online = online,
                                frame = remoteFrame,
                                subtitle = if (online) "Connessione attiva con $connectedName" else "Collega un secondo telefono per iniziare",
                                onClick = { selectedTab = if (online) "Live" else "Dispositivi" }
                            )

                            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                                MetricTile("DISPOSITIVI", if (online) "01" else "00", if (online) "1 collegato" else "Nessun collegamento", panel, primaryText, secondaryText, accent, Modifier.weight(1f))
                                MetricTile("STATO LIVE", if (remoteFrame != null) "LIVE" else "—", if (remoteFrame != null) "Video ricevuto" else "In attesa video", panel, primaryText, secondaryText, Violet, Modifier.weight(1f))
                                MetricTile("EVENTI", "—", "Non attivi", panel, primaryText, secondaryText, Color(0xFFFFB86B), Modifier.weight(1f))
                            }

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text("ACCESSO RAPIDO", fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = secondaryText)
                                    Text("Cosa vuoi fare?", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = primaryText)
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                QuickActionCard("Video live", "Guarda la telecamera", "◉", accent, panel, primaryText, secondaryText, Modifier.weight(1f)) { selectedTab = "Live" }
                                QuickActionCard("Dispositivi", "Collega un telefono", "⌁", Violet, panel, primaryText, secondaryText, Modifier.weight(1f)) { selectedTab = "Dispositivi" }
                            }

                            Card(
                                colors = CardDefaults.cardColors(containerColor = panel),
                                shape = RoundedCornerShape(20.dp),
                                border = androidx.compose.foundation.BorderStroke(1.dp, if (isDark) Color(0xFF202B3D) else Color(0xFFE1E8F1))
                            ) {
                                Row(Modifier.fillMaxWidth().padding(15.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Box(Modifier.size(44.dp).background(accent.copy(alpha = 0.10f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                                        Text("i", color = accent, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                                    }
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Text("Centro di controllo", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = primaryText)
                                        Text(if (online) "Il telefono è collegato. Apri Live per vedere il flusso." else "Apri Dispositivi e segui la guida per collegare i due telefoni.", fontSize = 11.sp, color = secondaryText, lineHeight = 16.sp)
                                    }
                                }
                            }
                            Spacer(Modifier.height(4.dp))
                        }
                    }
                    "Live" -> {
                        Column(
                            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            Text("Video live", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                            Text("La visuale della tua telecamera", fontSize = 14.sp, color = secondaryText)
                            if (remoteFrame != null) {
                                Card(colors = CardDefaults.cardColors(containerColor = Color.Black), shape = RoundedCornerShape(24.dp)) {
                                    Column {
                                        Image(bitmap = remoteFrame.asImageBitmap(), contentDescription = "Video live dalla telecamera", modifier = Modifier.fillMaxWidth().heightIn(min = 260.dp, max = 460.dp))
                                        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Box(Modifier.size(8.dp).background(Color(0xFFFF5964), RoundedCornerShape(50)))
                                            Spacer(Modifier.width(8.dp))
                                            Text("LIVE", color = Color(0xFFFF6474), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                                            Spacer(Modifier.weight(1f))
                                            Text("$receivedFrames frame ricevuti", color = Color.LightGray, fontSize = 10.sp)
                                        }
                                    }
                                }
                            } else {
                                LivePreviewPlaceholder(isDark = isDark, accent = accent)
                                EmptyStateCard("Nessun video ricevuto", "Quando il secondo telefono è collegato e invia il flusso, la visuale reale apparirà qui.", panel, primaryText, secondaryText, accent)
                            }
                            if (role == "camera" && connectedName != null) {
                                OutlinedButton(onClick = onSwitchCamera, modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("CAMBIA FOTOCAMERA") }
                            }
                            Text("STATO CONNESSIONE", fontSize = 10.sp, letterSpacing = 1.4.sp, color = secondaryText)
                            Text(status, fontSize = 12.sp, color = secondaryText)
                        }
                    }
                    "Dispositivi" -> {
                        Column(
                            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 4.dp),
                            verticalArrangement = Arrangement.spacedBy(15.dp)
                        ) {
                            Text("Dispositivi", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                            Text("Collega e gestisci i tuoi telefoni", fontSize = 14.sp, color = secondaryText)
                            ModeHeroCard(
                                title = if (role == "camera") "TELECAMERA" else "CENTRO DI CONTROLLO",
                                subtitle = if (role == "camera") "Questo telefono invia il video live" else "Questo telefono riceve il video live",
                                accent = if (role == "camera") accent else Violet,
                                symbol = if (role == "camera") "◉" else "⌂",
                                connected = online
                            )
                            Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(20.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.24f))) {
                                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
                                    Text("COLLEGA I DUE TELEFONI", color = accent, fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.7.sp)
                                    PairingInstruction("1", "Sul telefono che riceve il video, scegli CENTRO DI CONTROLLO.")
                                    PairingInstruction("2", "Sul telefono che riprende, scegli TELECAMERA e consenti l'accesso alla fotocamera.")
                                    PairingInstruction("3", "Attiva Bluetooth e Wi-Fi su entrambi. Concedi i permessi richiesti da Android.")
                                    PairingInstruction("4", "Avvia prima il centro di controllo; poi cerca il centro dal telefono telecamera.")
                                    PairingInstruction("5", "Seleziona COLLEGA quando appare il nome. Apri Live per vedere il video.")
                                    Text("Se non si trovano, interrompi la ricerca su entrambi e ripeti iniziando dal centro di controllo.", color = secondaryText, fontSize = 11.sp, lineHeight = 16.sp)
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                ModeMiniCard("TELECAMERA", "Invia video", role == "camera", accent, Modifier.weight(1f)) { onRole("camera") }
                                ModeMiniCard("CENTRO CONTROLLO", "Riceve video", role == "monitor", Violet, Modifier.weight(1f)) { onRole("monitor") }
                            }
                            Button(
                                onClick = onStart,
                                modifier = Modifier.fillMaxWidth().height(56.dp),
                                shape = RoundedCornerShape(17.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = if (role == "camera") accent else Violet, contentColor = Color(0xFF07101A))
                            ) {
                                Text(if (working) "RICERCA IN CORSO…" else if (role == "monitor") "RENDi VISIBILE IL CENTRO DI CONTROLLO" else "CERCA IL CENTRO DI CONTROLLO", fontWeight = FontWeight.ExtraBold, fontSize = 11.sp)
                            }
                            if (working || online) {
                                OutlinedButton(onClick = onStop, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(15.dp)) {
                                    Text(if (online) "SCOLLEGA DISPOSITIVO" else "INTERROMPI RICERCA")
                                }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Box(Modifier.size(9.dp).background(if (online) Color(0xFF55E6B1) else if (working) Color(0xFFFFC36B) else Color(0xFF718096), RoundedCornerShape(50)))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text(if (online) "DISPOSITIVO COLLEGATO" else if (working) "RICERCA IN CORSO" else "PRONTO PER L'ACCOPPIAMENTO", fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.7.sp, color = primaryText)
                                    Text(status, fontSize = 12.sp, color = secondaryText)
                                }
                            }
                            if (discovered.isNotEmpty()) {
                                Text("DISPOSITIVI TROVATI", fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = secondaryText)
                                discovered.forEach { item ->
                                    Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(18.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.35f))) {
                                        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                            Box(Modifier.size(44.dp).background(accent.copy(alpha = 0.10f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) { Text("◉", fontSize = 23.sp, color = accent) }
                                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                                Text(item.second, color = primaryText, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                                Text("SENTINEL ONE · nelle vicinanze", color = secondaryText, fontSize = 10.sp)
                                            }
                                            Button(onClick = { onConnect(item.first) }, shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color(0xFF07101A))) { Text("COLLEGA", fontWeight = FontWeight.Bold, fontSize = 10.sp) }
                                        }
                                    }
                                }
                            }
                            if (connectedName != null) EmptyStateCard("Connessione attiva", connectedName, panel, primaryText, secondaryText, Color(0xFF55E6B1))
                        }
                    }
                    "Eventi" -> {
                        Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text("Eventi", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                            Text("Attività e avvisi di sicurezza", fontSize = 14.sp, color = secondaryText)
                            LivePreviewPlaceholder(isDark = isDark, accent = Color(0xFFFFB86B))
                            EmptyStateCard("Cronologia non attiva", "Il rilevamento eventi non è ancora implementato. Quando sarà disponibile, gli avvisi reali compariranno qui.", panel, primaryText, secondaryText, Color(0xFFFFB86B))
                        }
                    }
                    else -> {
                        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text("Impostazioni", fontSize = 27.sp, fontWeight = FontWeight.ExtraBold, color = primaryText)
                            Text("Personalizza SENTINEL ONE", fontSize = 14.sp, color = secondaryText)
                            Card(colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(20.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.18f))) {
                                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                            Text("Aspetto", fontWeight = FontWeight.Bold, color = primaryText)
                                            Text(if (isDark) "Tema scuro attivo" else "Tema chiaro attivo", color = secondaryText, fontSize = 12.sp)
                                        }
                                        Switch(checked = isDark, onCheckedChange = { isDark = it })
                                    }
                                    HorizontalDivider(color = secondaryText.copy(alpha = 0.2f))
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                            Text("Modalità attuale", fontWeight = FontWeight.Bold, color = primaryText)
                                            Text(if (role == "camera") "Questo telefono invia il video" else "Questo telefono riceve il video", color = secondaryText, fontSize = 12.sp)
                                        }
                                        TextButton(onClick = { selectedTab = "Dispositivi" }) { Text("GESTISCI", color = accent) }
                                    }
                                    HorizontalDivider(color = secondaryText.copy(alpha = 0.2f))
                                    Text("Funzioni in sviluppo", fontWeight = FontWeight.Bold, color = primaryText)
                                    Text("Registrazione, rilevamento del movimento, notifiche e integrazioni con telecamere esterne non sono dichiarati attivi finché non sono implementati e verificati.", fontSize = 12.sp, color = secondaryText, lineHeight = 17.sp)
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
private fun SecurityHeroVisual(isDark: Boolean, online: Boolean, frame: Bitmap?, subtitle: String, onClick: () -> Unit) {
    val infinite = androidx.compose.animation.core.rememberInfiniteTransition(label = "security-hero")
    val pulse by infinite.animateFloat(
        initialValue = 0.72f,
        targetValue = 1f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(1500, easing = androidx.compose.animation.core.FastOutSlowInEasing),
            repeatMode = androidx.compose.animation.core.RepeatMode.Reverse
        ),
        label = "pulse"
    )
    val accent = Color(0xFF56E6F2)
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(26.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF101C2D)),
        border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.28f))
    ) {
        Box(Modifier.fillMaxWidth().height(230.dp).background(Brush.linearGradient(listOf(Color(0xFF152B43), Color(0xFF0B1220), Color(0xFF201D3B))))) {
            if (frame != null) {
                Image(
                    bitmap = frame.asImageBitmap(),
                    contentDescription = "Immagine reale ricevuta dalla telecamera",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
                Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color(0xE6101C2D), Color(0x66101C2D), Color.Transparent))))
            } else {
                androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
                val center = androidx.compose.ui.geometry.Offset(size.width * 0.73f, size.height * 0.46f)
                val base = size.minDimension * 0.20f
                for (i in 0..2) {
                    drawCircle(accent.copy(alpha = (0.12f - i * 0.025f).coerceAtLeast(0.025f) * pulse), base * (1.0f + i * 0.48f), center, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.4.dp.toPx()))
                }
                drawCircle(Color(0xFF9A7BFF).copy(alpha = 0.16f), base * 1.15f, center)
                drawCircle(Color(0xFF56E6F2).copy(alpha = 0.85f), base * 0.72f, center, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.dp.toPx()))
                drawCircle(Color(0xFF56E6F2).copy(alpha = 0.14f), base * 0.56f, center)
                drawCircle(Color(0xFFE8FBFF), base * 0.24f, center)
                // stylized camera lens and body
                val bodyW = base * 1.15f
                val bodyH = base * 0.78f
                drawRoundRect(Color(0xFF253C56), androidx.compose.ui.geometry.Offset(center.x - bodyW * 0.78f, center.y - bodyH * 0.5f), androidx.compose.ui.geometry.Size(bodyW * 1.2f, bodyH), androidx.compose.ui.geometry.CornerRadius(12.dp.toPx()))
                drawCircle(accent, base * 0.32f, center)
                drawCircle(Color(0xFF0B1220), base * 0.20f, center)
                drawCircle(accent.copy(alpha = pulse), base * 0.12f, center)
                // subtle scanline motif, deliberately decorative rather than a false camera feed
                for (i in 0..5) {
                    val yy = size.height * 0.17f + i * 13.dp.toPx()
                    drawLine(Color.White.copy(alpha = 0.035f), androidx.compose.ui.geometry.Offset(size.width * 0.48f, yy), androidx.compose.ui.geometry.Offset(size.width * 0.94f, yy), 1.dp.toPx())
                }
            }
            }
            Column(Modifier.align(Alignment.CenterStart).fillMaxWidth(0.60f).padding(start = 18.dp, top = 18.dp, bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Surface(color = accent.copy(alpha = 0.12f), shape = RoundedCornerShape(50)) {
                    Text(if (online) "● SISTEMA COLLEGATO" else "● SISTEMA PRONTO", Modifier.padding(horizontal = 10.dp, vertical = 6.dp), color = accent, fontSize = 9.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.5.sp)
                }
                Text("La casa,\nsotto controllo.", color = Color.White, fontSize = 24.sp, lineHeight = 29.sp, fontWeight = FontWeight.ExtraBold)
                Text(subtitle, color = Color(0xFFB9C7D9), fontSize = 11.sp, lineHeight = 15.sp, maxLines = 3)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(if (online) "APRI VIDEO LIVE" else "CONFIGURA ORA", color = accent, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.5.sp)
                    Text("→", color = accent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun LivePreviewPlaceholder(isDark: Boolean, accent: Color) {
    val infinite = androidx.compose.animation.core.rememberInfiniteTransition(label = "live-placeholder")
    val scan by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = androidx.compose.animation.core.infiniteRepeatable(
            animation = androidx.compose.animation.core.tween(2400, easing = androidx.compose.animation.core.LinearEasing),
            repeatMode = androidx.compose.animation.core.RepeatMode.Restart
        ),
        label = "scan"
    )
    Box(
        Modifier.fillMaxWidth().height(190.dp).background(
            Brush.linearGradient(listOf(Color(0xFF0B1421), Color(0xFF14243A), Color(0xFF10172B))),
            RoundedCornerShape(22.dp)
        )
    ) {
        androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) {
            val grid = Color(0xFF5C7895).copy(alpha = 0.16f)
            val gap = 24.dp.toPx()
            var x = 0f
            while (x < size.width) {
                drawLine(grid, androidx.compose.ui.geometry.Offset(x, 0f), androidx.compose.ui.geometry.Offset(x, size.height), 1f)
                x += gap
            }
            var y = 0f
            while (y < size.height) {
                drawLine(grid, androidx.compose.ui.geometry.Offset(0f, y), androidx.compose.ui.geometry.Offset(size.width, y), 1f)
                y += gap
            }
            val lineY = size.height * scan
            drawLine(accent.copy(alpha = 0.42f), androidx.compose.ui.geometry.Offset(0f, lineY), androidx.compose.ui.geometry.Offset(size.width, lineY), 2.dp.toPx())
            drawCircle(accent.copy(alpha = 0.16f), 39.dp.toPx(), androidx.compose.ui.geometry.Offset(size.width / 2, size.height / 2))
            drawCircle(accent.copy(alpha = 0.8f), 25.dp.toPx(), androidx.compose.ui.geometry.Offset(size.width / 2, size.height / 2), style = androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
        }
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text("◉", color = accent, fontSize = 34.sp)
            Text("ANTEPRIMA VIDEO", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.2.sp)
            Text("In attesa del flusso reale", color = Color(0xFF9BAAC0), fontSize = 10.sp)
        }
        Surface(Modifier.align(Alignment.TopStart).padding(12.dp), color = Color.Black.copy(alpha = 0.42f), shape = RoundedCornerShape(7.dp)) {
            Text("SENTINEL · LIVE", Modifier.padding(horizontal = 8.dp, vertical = 5.dp), color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun QuickActionCard(
    title: String,
    subtitle: String,
    symbol: String,
    accent: Color,
    panel: Color,
    primary: Color,
    secondary: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(onClick = onClick, modifier = modifier, colors = CardDefaults.cardColors(containerColor = panel), shape = RoundedCornerShape(20.dp), border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.22f))) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.size(42.dp).background(accent.copy(alpha = 0.12f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                Text(symbol, color = accent, fontSize = 23.sp, fontWeight = FontWeight.Bold)
            }
            Text(title, color = primary, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = secondary, fontSize = 10.sp, lineHeight = 14.sp)
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
