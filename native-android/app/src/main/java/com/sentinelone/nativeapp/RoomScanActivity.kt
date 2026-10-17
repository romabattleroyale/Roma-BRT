package com.sentinelone.nativeapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.ar.core.Config
import com.google.ar.core.Session
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val ScanNight = Color(0xFF080B13)
private val ScanPanel = Color(0xFF111827)
private val ScanCyan = Color(0xFF53E5F2)
private val ScanViolet = Color(0xFF9A7BFF)

class RoomScanActivity : ComponentActivity() {
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var previewView by mutableStateOf<PreviewView?>(null)
    private var cameraReady by mutableStateOf(false)
    private var arStatus by mutableStateOf("Verifica ARCore in corso…")
    private var depthSupported by mutableStateOf(false)
    private var cameraMessage by mutableStateOf("Preparazione fotocamera…")
    private var roomName by mutableStateOf("Soggiorno")
    private var photoCount by mutableIntStateOf(0)
    private var isRecording by mutableStateOf(false)
    private var lastSaved by mutableStateOf("Nessun file acquisito")

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startCamera() else cameraMessage = "Permesso fotocamera negato. Abilitalo nelle impostazioni Android."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        roomName = intent.getStringExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME)?.takeIf { it.isNotBlank() } ?: "Soggiorno"
        refreshCaptureSummary()
        checkArCoreDepth()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = ScanCyan, secondary = ScanViolet, background = ScanNight, surface = ScanPanel, onBackground = Color.White, onSurface = Color.White)) {
                RoomScanScreen(roomName, { newName -> roomName = newName; refreshCaptureSummary() }, arStatus, depthSupported, cameraMessage, cameraReady, previewView, photoCount, isRecording, lastSaved, { capturePhoto() }, { toggleRecording() }, { finish() }, { startActivity(Intent(this, HouseReconstructionActivity::class.java).putExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME, roomName)) }, { startActivity(Intent(this, HouseArScanActivity::class.java).putExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME, roomName)) })
            }
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCamera()
        else permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    override fun onResume() {
        super.onResume()
        refreshCaptureSummary()
    }

    private fun refreshCaptureSummary() {
        val files = outputDirectory().listFiles()
            ?.filter { it.isFile && it.extension.lowercase() in setOf("jpg", "jpeg", "mp4") }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()
        photoCount = files.count { it.extension.lowercase() in setOf("jpg", "jpeg") }
        lastSaved = files.firstOrNull()?.name ?: "Nessun file acquisito"
    }

    private fun checkArCoreDepth() {
        // checkAvailability() may initially return UNKNOWN_CHECKING on a cold start.
        // Do not treat every non-supported enum value as a definite incompatibility.
        try {
            val availability = com.google.ar.core.ArCoreApk.getInstance().checkAvailability(this)
            when {
                availability.isSupported -> inspectArCoreDepth()
                availability.isTransientFailure -> {
                    depthSupported = false
                    arStatus = "Verifica ARCore in corso o rete non disponibile. Riprova tra qualche secondo; foto e video sono già utilizzabili."
                }
                else -> {
                    depthSupported = false
                    arStatus = "ARCore non risulta disponibile (" + availability.name + "). Aggiorna Google Play Services for AR e riprova; foto/video sono salvati ma non generano ancora la piantina."
                }
            }
        } catch (e: Exception) {
            depthSupported = false
            arStatus = "Verifica ARCore non riuscita (" + e.javaClass.simpleName + "). Foto/video vengono salvati, ma non ricostruiscono da soli la stanza."
        }
    }

    private fun inspectArCoreDepth() {
        try {
            val session = Session(this)
            try {
                depthSupported = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
                arStatus = if (depthSupported) {
                    "ARCore e Depth API disponibili. Avvia la scansione AR per stimare i piani; foto/video restano riferimenti."
                } else {
                    "ARCore disponibile, Depth API non supportata. La scansione dei piani può essere disponibile senza profondità; foto/video non generano da soli la piantina."
                }
            } finally {
                session.close()
            }
        } catch (e: Exception) {
            depthSupported = false
            arStatus = "ARCore rilevato ma sessione non inizializzabile (" + e.javaClass.simpleName + "). Aggiorna Google Play Services for AR e riprova."
        }
    }

    private fun startCamera() {
        cameraMessage = "Avvio fotocamera…"
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val provider = future.get()
                cameraProvider = provider
                val preview = Preview.Builder().build()
                val capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).build()
                val recorder = Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD)).build()
                val video = VideoCapture.withOutput(recorder)
                val view = PreviewView(this).apply {
                    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                }
                preview.setSurfaceProvider(view.surfaceProvider)
                provider.unbindAll()
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture, video)
                previewView = view
                imageCapture = capture
                videoCapture = video
                cameraReady = true
                cameraMessage = "Fotocamera pronta · inquadra tutta la stanza"
            } catch (e: Exception) {
                cameraReady = false
                cameraMessage = "Fotocamera non disponibile: " + (e.localizedMessage ?: e.javaClass.simpleName)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun outputDirectory(): File {
        val base = getExternalFilesDir(Environment.DIRECTORY_PICTURES) ?: filesDir
        val scanRoot = File(base, "SENTINEL_ONE_SCAN")
        val directory = roomCaptureDirectory(scanRoot, roomName)
        if (!directory.exists()) directory.mkdirs()
        runCatching {
            val marker = File(directory, ".sentinel-room-name")
            if (!marker.isFile) marker.writeText(roomName.trim().ifBlank { "Stanza" })
        }
        return directory
    }

    private fun newOutput(prefix: String, extension: String): File {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.ITALY).format(Date())
        return File(outputDirectory(), prefix + "_" + stamp + "." + extension)
    }

    private fun capturePhoto() {
        val capture = imageCapture ?: run { cameraMessage = "Attendi che la fotocamera sia pronta"; return }
        val file = newOutput("foto", "jpg")
        capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(this), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                photoCount += 1
                lastSaved = file.name
                cameraMessage = "Foto salvata · " + photoCount + " foto per questa stanza"
            }
            override fun onError(exception: ImageCaptureException) { cameraMessage = "Errore foto: " + exception.localizedMessage }
        })
    }

    private fun toggleRecording() {
        if (isRecording) {
            recording?.stop()
            recording = null
            isRecording = false
            cameraMessage = "Arresto registrazione…"
            return
        }
        val video = videoCapture ?: run { cameraMessage = "Attendi che la fotocamera sia pronta"; return }
        val file = newOutput("percorso", "mp4")
        recording = video.output.prepareRecording(this, FileOutputOptions.Builder(file).build()).start(ContextCompat.getMainExecutor(this)) { event ->
            when (event) {
                is VideoRecordEvent.Start -> {
                    isRecording = true
                    cameraMessage = "Video in registrazione · cammina lentamente lungo le pareti"
                }
                is VideoRecordEvent.Finalize -> {
                    isRecording = false
                    recording = null
                    if (event.hasError()) {
                        cameraMessage = "Video non riuscito (codice " + event.error + ")"
                        file.delete()
                    } else {
                        lastSaved = file.name
                        cameraMessage = "Video salvato · riprendi angoli, porte e finestre"
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        recording?.stop()
        recording = null
        cameraProvider?.unbindAll()
        super.onDestroy()
    }
}

@Composable
private fun RoomScanScreen(
    roomName: String, onRoomName: (String) -> Unit, arStatus: String, depthSupported: Boolean,
    cameraMessage: String, cameraReady: Boolean, previewView: PreviewView?, photoCount: Int,
    isRecording: Boolean, lastSaved: String, onCapturePhoto: () -> Unit, onToggleRecording: () -> Unit, onBack: () -> Unit, onOpenReconstruction: () -> Unit, onOpenArScan: () -> Unit
) {
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF101A2B), ScanNight, ScanNight))).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(13.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = onBack) { Text("← INDIETRO") }
            Spacer(Modifier.width(10.dp))
            Column {
                Text("HOME BUILDER", color = ScanCyan, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.4.sp)
                Text("Scansione stanza", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = ScanPanel), shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("1 · NOME STANZA", color = ScanViolet, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                OutlinedTextField(value = roomName, onValueChange = onRoomName, modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text("Es. Soggiorno") })
                Text("I file vengono separati per stanza.", color = Color(0xFF9BA8BC), fontSize = 11.sp)
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = ScanPanel), shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                Text("2 · ACQUISIZIONE GUIDATA", color = ScanCyan, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                Box(Modifier.fillMaxWidth().height(280.dp).background(Color.Black, RoundedCornerShape(15.dp)), contentAlignment = Alignment.Center) {
                    if (previewView != null && cameraReady) AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())
                    else CircularProgressIndicator(color = ScanCyan)
                }
                Text(cameraMessage, color = if (isRecording) Color(0xFFFF737D) else Color(0xFFB7C5D8), fontSize = 12.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = onCapturePhoto, enabled = cameraReady && !isRecording, modifier = Modifier.weight(1f).height(50.dp), colors = ButtonDefaults.buttonColors(containerColor = ScanCyan, contentColor = Color(0xFF07101A))) { Text("◎ FOTO", fontWeight = FontWeight.ExtraBold) }
                    Button(onClick = onToggleRecording, enabled = cameraReady, modifier = Modifier.weight(1f).height(50.dp), colors = ButtonDefaults.buttonColors(containerColor = if (isRecording) Color(0xFFFF5964) else ScanViolet)) { Text(if (isRecording) "■ FERMA" else "● VIDEO", fontWeight = FontWeight.ExtraBold) }
                }
                Text("Foto: " + photoCount + " · Ultimo file: " + lastSaved, color = Color(0xFF9BA8BC), fontSize = 10.sp)
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = ScanPanel), shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("3 · COME MUOVERSI", color = ScanViolet, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                Text("• Inizia dalla porta e inquadra l'intera stanza.\n• Cammina lentamente lungo ogni parete.\n• Riprendi gli angoli, le porte e le finestre.\n• Evita zoom, controluce e movimenti bruschi.\n• Salva foto aggiuntive dei dettagli.", color = Color(0xFFCFD8E6), fontSize = 12.sp, lineHeight = 19.sp)
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = ScanPanel), shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("4 · SUPPORTO ARCORE", color = ScanCyan, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                Text(arStatus, color = if (depthSupported) Color(0xFF55E6B1) else Color(0xFFFFC36B), fontSize = 12.sp)
                Text("Importante: in questa versione foto e video vengono soltanto salvati come riferimenti; non vengono analizzati per ricavare la piantina. Per ottenere una stima automatica devi usare la scansione AR quando il dispositivo la supporta. Se ARCore non parte, l'editor 2D/3D resta manuale.", color = Color(0xFFFFC36B), fontSize = 11.sp, lineHeight = 17.sp)
            }
        }
        Button(onClick = onOpenArScan, modifier = Modifier.fillMaxWidth().height(52.dp), colors = ButtonDefaults.buttonColors(containerColor = ScanCyan, contentColor = Color(0xFF07101A))) { Text("AVVIA SCANSIONE AR · PAVIMENTO E PARETI", fontWeight = FontWeight.ExtraBold, fontSize = 10.sp) }
        Button(onClick = onOpenReconstruction, modifier = Modifier.fillMaxWidth().height(52.dp), colors = ButtonDefaults.buttonColors(containerColor = ScanViolet)) { Text("APRI EDITOR PIANTINA 2D / MODELLO 3D", fontWeight = FontWeight.ExtraBold) }
        Spacer(Modifier.height(12.dp))
    }
}
