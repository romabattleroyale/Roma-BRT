package com.sentinelone.nativeapp

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.SceneView
import io.github.sceneview.math.Position
import io.github.sceneview.math.Size as SceneSize
import io.github.sceneview.node.CubeNode
import io.github.sceneview.rememberCameraManipulator
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberModelLoader
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import kotlinx.coroutines.delay
import kotlin.math.min
import java.util.concurrent.atomic.AtomicInteger

private val HouseBg = Color(0xFF080B13)
private val HousePanel = Color(0xFF111827)
private val HouseCyan = Color(0xFF53E5F2)
private val HouseMuted = Color(0xFF9BA8BC)

data class HouseOpening(val id: String = UUID.randomUUID().toString(), val wall: String, val type: String, val offset: Float, val width: Float, val height: Float)
data class HouseGeometry(val width: Float = 5f, val depth: Float = 4f, val height: Float = 2.7f, val openings: List<HouseOpening> = emptyList(), val scaleConfirmed: Boolean = false)
private data class ScanAsset(val name: String, val kind: String, val sizeBytes: Long)

private fun normalizedRoomName(raw: String): String =
    raw.trim().replace(Regex("[^A-Za-z0-9À-ÿ_-]+"), "_").trim('_').ifBlank { "Stanza" }

private fun normalizeOpenings(openings: List<HouseOpening>, roomWidth: Float, roomDepth: Float): List<HouseOpening> {
    val normalized = mutableListOf<HouseOpening>()
    listOf("Nord", "Sud", "Est", "Ovest").forEach { wall ->
        val wallLength = if (wall == "Nord" || wall == "Sud") roomWidth else roomDepth
        var cursor = 0f
        openings.filter { it.wall == wall }.sortedBy { it.offset }.forEach { opening ->
            val available = (wallLength - cursor).coerceAtLeast(0f)
            if (available >= 0.5f) {
                val width = opening.width.coerceIn(0.5f, minOf(available, wallLength))
                val offset = opening.offset.coerceIn(cursor, (wallLength - width).coerceAtLeast(cursor))
                val height = if (opening.type == "Porta") {
                    opening.height.coerceIn(1.8f, 2.4f)
                } else {
                    opening.height.coerceIn(0.6f, 2.0f)
                }
                normalized += opening.copy(offset = offset, width = width, height = height)
                cursor = offset + width + 0.1f
            }
        }
    }
    return normalized
}

private fun findFreeOpeningOffset(length: Float, width: Float, existing: List<HouseOpening>): Float? {
    val minimumGap = 0.1f
    var cursor = 0f
    existing.sortedBy { it.offset }.forEach { opening ->
        val start = opening.offset.coerceIn(0f, length)
        val end = (opening.offset + opening.width).coerceIn(start, length)
        val freeEnd = (start - minimumGap).coerceAtLeast(cursor)
        if (freeEnd - cursor >= width) return cursor + (freeEnd - cursor - width) / 2f
        cursor = maxOf(cursor, end + minimumGap)
    }
    return if (length - cursor >= width) cursor + (length - cursor - width) / 2f else null
}

private fun arEvidenceFile(filesDir: File, roomName: String) =
    File(filesDir, "sentinel_ar_scan_" + normalizedRoomName(roomName) + ".json")

private object HouseProjectRepository {
    private fun projectFileName(roomName: String) = "sentinel_house_project_" + normalizedRoomName(roomName) + ".json"

    fun load(dir: File, roomName: String): HouseGeometry = runCatching {
        val roomFile = File(dir, projectFileName(roomName))
        // Read the pre-room-specific project as a one-time compatibility fallback for the default room.
        val source = if (roomFile.exists()) roomFile else if (normalizedRoomName(roomName) == "Stanza") File(dir, "sentinel_house_project.json") else roomFile
        val j = JSONObject(source.readText())
        val a = j.optJSONArray("openings") ?: JSONArray()
        HouseGeometry(j.optDouble("width", 5.0).toFloat().coerceIn(2f, 8f), j.optDouble("depth", 4.0).toFloat().coerceIn(2f, 8f), j.optDouble("height", 2.7).toFloat().coerceIn(2.2f, 4f), (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            HouseOpening(o.optString("id", UUID.randomUUID().toString()), o.optString("wall", "Nord"), o.optString("type", "Porta"), o.optDouble("offset", .5).toFloat(), o.optDouble("width", .9).toFloat(), o.optDouble("height", 2.05).toFloat())
        }, j.optBoolean("scaleConfirmed", false))
    }.getOrDefault(HouseGeometry())

    fun save(dir: File, roomName: String, g: HouseGeometry) {
        val a = JSONArray()
        g.openings.forEach { o -> a.put(JSONObject().put("id", o.id).put("wall", o.wall).put("type", o.type).put("offset", o.offset).put("width", o.width).put("height", o.height)) }
        File(dir, projectFileName(roomName)).writeText(JSONObject().put("version", 2).put("roomName", roomName).put("width", g.width).put("depth", g.depth).put("height", g.height).put("scaleConfirmed", g.scaleConfirmed).put("openings", a).toString(2))
    }
}

class HouseReconstructionActivity : ComponentActivity() {
    companion object {
        const val EXTRA_ROOM_NAME = "com.sentinelone.nativeapp.EXTRA_ROOM_NAME"
    }

    private var currentRoomName: String = "Stanza"
    private var scanAssets by mutableStateOf<List<ScanAsset>>(emptyList())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentRoomName = intent.getStringExtra(EXTRA_ROOM_NAME)?.takeIf { it.isNotBlank() } ?: "Stanza"
        val initial = HouseProjectRepository.load(filesDir, currentRoomName)
        refreshScanAssets()
        setContent { MaterialTheme(colorScheme = darkColorScheme(primary = HouseCyan, secondary = Color(0xFF9A7BFF), background = HouseBg, surface = HousePanel, onSurface = Color.White)) {
            HouseEditor(initial, currentRoomName, scanAssets, { HouseProjectRepository.save(filesDir, currentRoomName, it) }, { finish() })
        } }
    }

    override fun onResume() {
        super.onResume()
        refreshScanAssets()
    }

    private fun refreshScanAssets() {
        val base = getExternalFilesDir(Environment.DIRECTORY_PICTURES) ?: filesDir
        val roomDir = File(File(base, "SENTINEL_ONE_SCAN"), normalizedRoomName(currentRoomName))
        val captures = roomDir.listFiles()
            ?.filter { it.isFile && it.extension.lowercase() in setOf("jpg", "jpeg", "mp4") }
            ?.sortedByDescending { it.lastModified() }
            ?.map { file -> ScanAsset(file.name, if (file.extension.lowercase() == "mp4") "VIDEO" else "FOTO", file.length()) }
            ?: emptyList()
        val arFile = arEvidenceFile(filesDir, currentRoomName)
        scanAssets = captures + if (arFile.isFile) listOf(ScanAsset("Scansione AR salvata", "AR", arFile.length())) else emptyList()
    }
}

@Composable
private fun HouseEditor(initial: HouseGeometry, roomName: String, scanAssets: List<ScanAsset>, save: (HouseGeometry) -> Unit, back: () -> Unit) {
    var g by remember { mutableStateOf(initial) }
    var wall by remember { mutableStateOf("Nord") }
    var type by remember { mutableStateOf("Porta") }
    var message by remember { mutableStateOf("Progetto pronto") }

    LaunchedEffect(g) {
        delay(600)
        message = try {
            save(g)
            "Bozza salvata automaticamente"
        } catch (_: Exception) {
            "Salvataggio automatico non riuscito"
        }
    }

    Column(Modifier.fillMaxSize().background(HouseBg).statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { OutlinedButton(onClick = back) { Text("INDIETRO") }; Column { Text("SENTINEL ONE", color = HouseCyan); Text("Ricostruzione 2D/3D", color = Color.White, fontSize = 21.sp) } }
        Text("STANZA · $roomName", color = HouseMuted, fontSize = 12.sp)
        Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("ACQUISIZIONI DI QUESTA STANZA", color = HouseCyan)
                Text("${scanAssets.count { it.kind == "FOTO" }} foto · ${scanAssets.count { it.kind == "VIDEO" }} video", color = Color.White, fontSize = 13.sp)
                if (scanAssets.isEmpty()) {
                    Text("Non ci sono ancora foto o video salvati per questa stanza.", color = HouseMuted, fontSize = 12.sp)
                } else {
                    scanAssets.take(12).forEach { asset ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(asset.kind, color = when (asset.kind) { "VIDEO" -> Color(0xFF9A7BFF); "AR" -> Color(0xFFFFC36B); else -> HouseCyan }, fontSize = 10.sp)
                            Text(asset.name, Modifier.weight(1f), color = Color.White, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(if (asset.sizeBytes < 1024L * 1024L) "${asset.sizeBytes / 1024L} KB" else "%.1f MB".format(asset.sizeBytes / (1024f * 1024f)), color = HouseMuted, fontSize = 10.sp)
                        }
                    }
                    if (scanAssets.size > 12) Text("Mostrati gli ultimi 12 file su ${scanAssets.size}.", color = HouseMuted, fontSize = 10.sp)
                }
                if (scanAssets.any { it.kind == "AR" }) {
                    Text("È disponibile una stima AR provvisoria. Verifica larghezza e profondità e conferma la scala con misure reali.", color = Color(0xFFFFC36B), fontSize = 11.sp)
                }
                Text("Le foto e i video restano associati alla stanza. Le aperture non vengono dedotte automaticamente dalle immagini in questa versione.", color = HouseMuted, fontSize = 11.sp)
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("PIANTINA 2D · METRI", color = HouseCyan)
                FloorPlan(g, Modifier.fillMaxWidth().height(220.dp))
                Text("Larghezza: %.1f m".format(g.width), color = Color.White)
                Slider(g.width, { value -> g = g.copy(width = value, openings = normalizeOpenings(g.openings, value, g.depth), scaleConfirmed = false) }, valueRange = 2f..8f)
                Text("Profondità: %.1f m".format(g.depth), color = Color.White)
                Slider(g.depth, { value -> g = g.copy(depth = value, openings = normalizeOpenings(g.openings, g.width, value), scaleConfirmed = false) }, valueRange = 2f..8f)
                Text("Altezza pareti: %.1f m".format(g.height), color = Color.White)
                Slider(g.height, { g = g.copy(height = it) }, valueRange = 2.2f..4f)
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Checkbox(g.scaleConfirmed, { g = g.copy(scaleConfirmed = it) })
                    Text("Scala confermata da misura reale", color = Color.White, fontSize = 12.sp)
                }
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("PORTE E FINESTRE", color = HouseCyan)
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) { listOf("Nord", "Est", "Sud", "Ovest").forEach { s -> FilterChip(wall == s, { wall = s }, label = { Text(s) }) } }
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    FilterChip(type == "Porta", { type = "Porta" }, label = { Text("Porta") })
                    FilterChip(type == "Finestra", { type = "Finestra" }, label = { Text("Finestra") })
                    Spacer(Modifier.weight(1f))
                    Button(onClick = {
                        val len = if (wall == "Nord" || wall == "Sud") g.width else g.depth
                        val w = if (type == "Porta") .9f else 1.2f
                        val existing = g.openings.filter { it.wall == wall }
                        val freeOffset = findFreeOpeningOffset(len, w, existing)
                        if (freeOffset != null) {
                            g = g.copy(openings = g.openings + HouseOpening(wall = wall, type = type, offset = freeOffset, width = w, height = if (type == "Porta") 2.05f else 1.2f))
                            message = type + " aggiunta"
                        } else message = "Spazio insufficiente sulla parete selezionata"
                    }) { Text("AGGIUNGI") }
                }
                g.openings.forEach { o ->
                    val wallLength = if (o.wall == "Nord" || o.wall == "Sud") g.width else g.depth
                    val maxWidth = (wallLength - 0.2f).coerceAtLeast(0.5f)
                    val safeWidth = o.width.coerceIn(0.5f, maxWidth)
                    val safeOffset = o.offset.coerceIn(0f, (wallLength - safeWidth).coerceAtLeast(0f))
                    val peers = g.openings.filter { it.wall == o.wall && it.id != o.id }
                    val leftLimit = peers.filter { it.offset + it.width <= safeOffset + 0.001f }
                        .maxOfOrNull { it.offset + it.width }?.coerceIn(0f, wallLength) ?: 0f
                    val rightLimit = peers.filter { it.offset >= safeOffset + safeWidth - 0.001f }
                        .minOfOrNull { it.offset }?.coerceIn(0f, wallLength) ?: wallLength
                    val minOffset = leftLimit.coerceIn(0f, (wallLength - safeWidth).coerceAtLeast(0f))
                    val maxOffset = (rightLimit - safeWidth).coerceIn(minOffset, (wallLength - safeWidth).coerceAtLeast(minOffset))
                    val editableOffset = safeOffset.coerceIn(minOffset, maxOffset)
                    val editableMaxWidth = (rightLimit - editableOffset).coerceAtLeast(0.5f).coerceAtMost(maxWidth)
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(o.type + " · " + o.wall + " · %.1f m".format(safeWidth), Modifier.weight(1f), color = Color.White, fontSize = 12.sp)
                            TextButton(onClick = { g = g.copy(openings = g.openings.filterNot { it.id == o.id }) }) { Text("RIMUOVI") }
                        }
                        Text("Posizione sulla parete: %.1f m".format(editableOffset), color = HouseMuted, fontSize = 10.sp)
                        Slider(value = editableOffset, onValueChange = { value ->
                            g = g.copy(openings = g.openings.map { item ->
                                if (item.id == o.id) item.copy(offset = value.coerceIn(minOffset, maxOffset)) else item
                            })
                        }, valueRange = minOffset..maxOffset)
                        Text("Larghezza: %.1f m".format(safeWidth), color = HouseMuted, fontSize = 10.sp)
                        Slider(value = safeWidth.coerceAtMost(editableMaxWidth), onValueChange = { value ->
                            g = g.copy(openings = g.openings.map { item ->
                                if (item.id == o.id) item.copy(width = value, offset = item.offset.coerceIn(minOffset, (rightLimit - value).coerceAtLeast(minOffset))) else item
                            })
                        }, valueRange = 0.5f..editableMaxWidth)
                        val minOpeningHeight = if (o.type == "Porta") 1.8f else 0.6f
                        val maxOpeningHeight = if (o.type == "Porta") minOf(2.4f, g.height) else minOf(2.0f, (g.height - 0.9f).coerceAtLeast(0.6f))
                        val safeOpeningHeight = o.height.coerceIn(minOpeningHeight.coerceAtMost(maxOpeningHeight), maxOpeningHeight.coerceAtLeast(minOpeningHeight))
                        Text("Altezza apertura: %.1f m".format(safeOpeningHeight), color = HouseMuted, fontSize = 10.sp)
                        Slider(value = safeOpeningHeight, onValueChange = { value ->
                            g = g.copy(openings = g.openings.map { item ->
                                if (item.id == o.id) item.copy(height = value) else item
                            })
                        }, valueRange = minOpeningHeight.coerceAtMost(maxOpeningHeight)..maxOpeningHeight.coerceAtLeast(minOpeningHeight))
                    }
                }
            }
        }
        Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
            Column(Modifier.fillMaxWidth().padding(10.dp)) {
                Text("MODELLO 3D · FILAMENT", color = HouseCyan)
                House3D(g, Modifier.fillMaxWidth().height(270.dp))
                Text("Trascina per ruotare il modello.", color = HouseMuted, fontSize = 10.sp)
            }
        }
        Text(message, color = HouseMuted)
        Button(onClick = {
            message = try {
                save(g)
                "Progetto salvato sul dispositivo"
            } catch (_: Exception) {
                "Errore durante il salvataggio del progetto"
            }
        }, modifier = Modifier.fillMaxWidth()) { Text("SALVA PROGETTO 2D/3D") }
    }
}

@Composable
private fun FloorPlan(g: HouseGeometry, modifier: Modifier = Modifier) {
    Canvas(modifier.background(Color(0xFF090F19), RoundedCornerShape(12.dp))) {
        val m = 22f
        val s = min((size.width - 2*m) / g.width, (size.height - 2*m) / g.depth)
        val w = g.width*s; val h = g.depth*s; val l = (size.width-w)/2; val t = (size.height-h)/2; val r=l+w; val b=t+h
        drawRect(Color(0xFF152338), Offset(l,t), androidx.compose.ui.geometry.Size(w,h))
        drawLine(HouseCyan, Offset(l,t), Offset(r,t), 7f, cap=StrokeCap.Round); drawLine(HouseCyan, Offset(r,t), Offset(r,b), 7f, cap=StrokeCap.Round)
        drawLine(HouseCyan, Offset(r,b), Offset(l,b), 7f, cap=StrokeCap.Round); drawLine(HouseCyan, Offset(l,b), Offset(l,t), 7f, cap=StrokeCap.Round)
        g.openings.forEach { o ->
            val horizontal = o.wall == "Nord" || o.wall == "Sud"; val len = if (horizontal) g.width else g.depth
            val p1 = (o.offset/len).coerceIn(0f,1f); val p2 = ((o.offset+o.width)/len).coerceIn(p1,1f)
            val c = if (o.type == "Porta") Color(0xFFFFC36B) else Color(0xFF9A7BFF)
            if (horizontal) { val y = if (o.wall == "Nord") t else b; drawLine(Color(0xFF090F19), Offset(l+w*p1,y), Offset(l+w*p2,y), 10f); drawLine(c, Offset(l+w*p1,y), Offset(l+w*p2,y), 4f) }
            else { val x = if (o.wall == "Est") r else l; drawLine(Color(0xFF090F19), Offset(x,t+h*p1), Offset(x,t+h*p2), 10f); drawLine(c, Offset(x,t+h*p1), Offset(x,t+h*p2), 4f) }
        }
    }
}

@Composable
private fun House3D(g: HouseGeometry, modifier: Modifier = Modifier) {
    val engine = rememberEngine(); val loader = rememberModelLoader(engine)
    val t = .12f; val hw = g.width/2; val hd = g.depth/2
    Box(modifier.background(Color(0xFF090F19), RoundedCornerShape(12.dp))) {
        SceneView(Modifier.fillMaxSize(), engine = engine, modelLoader = loader, cameraManipulator = rememberCameraManipulator()) {
            CubeNode(size = SceneSize(x=g.width,y=.08f,z=g.depth), position=Position(y=-.05f))
            listOf("Nord","Sud").forEach { side ->
                val z = if (side=="Nord") -hd else hd
                val opens = g.openings.filter { it.wall==side }
                wallSegments(g.width, opens).forEach { seg -> CubeNode(size=SceneSize(x=seg.second-seg.first,y=g.height,z=t), position=Position(x=-hw+(seg.first+seg.second)/2,y=g.height/2,z=z)) }
                opens.forEach { o ->
                    val start=o.offset.coerceIn(0f,g.width)
                    val end=(start+o.width).coerceIn(start,g.width)
                    val openingHeight = o.height
                    val sill = if (o.type=="Porta") 0f else 0.9f.coerceAtMost(g.height)
                    val openingTop=(sill+openingHeight).coerceAtMost(g.height)
                    val below=sill.coerceAtLeast(0f)
                    val above=(g.height-openingTop).coerceAtLeast(0f)
                    if (below > 0.05f) CubeNode(size=SceneSize(x=end-start,y=below,z=t),position=Position(x=-hw+(start+end)/2,y=below/2,z=z))
                    if (above > 0.05f) CubeNode(size=SceneSize(x=end-start,y=above,z=t),position=Position(x=-hw+(start+end)/2,y=openingTop+above/2,z=z))
                }
            }
            listOf("Ovest","Est").forEach { side ->
                val x = if (side=="Ovest") -hw else hw
                val opens = g.openings.filter { it.wall==side }
                wallSegments(g.depth, opens).forEach { seg -> CubeNode(size=SceneSize(x=t,y=g.height,z=seg.second-seg.first), position=Position(x=x,y=g.height/2,z=-hd+(seg.first+seg.second)/2)) }
                opens.forEach { o ->
                    val start=o.offset.coerceIn(0f,g.depth)
                    val end=(start+o.width).coerceIn(start,g.depth)
                    val openingHeight = o.height
                    val sill = if (o.type=="Porta") 0f else 0.9f.coerceAtMost(g.height)
                    val openingTop=(sill+openingHeight).coerceAtMost(g.height)
                    val below=sill.coerceAtLeast(0f)
                    val above=(g.height-openingTop).coerceAtLeast(0f)
                    if (below > 0.05f) CubeNode(size=SceneSize(x=t,y=below,z=end-start),position=Position(x=x,y=below/2,z=-hd+(start+end)/2))
                    if (above > 0.05f) CubeNode(size=SceneSize(x=t,y=above,z=end-start),position=Position(x=x,y=openingTop+above/2,z=-hd+(start+end)/2))
                }
            }
        }
    }
}
private fun wallSegments(length: Float, openings: List<HouseOpening>): List<Pair<Float,Float>> {
    val out=mutableListOf<Pair<Float,Float>>(); var cursor=0f
    openings.sortedBy { it.offset }.forEach { o -> val start=o.offset.coerceIn(cursor,length); val end=(start+o.width).coerceIn(start,length); if(start-cursor>.05f) out += cursor to start; cursor=maxOf(cursor,end) }
    if(length-cursor>.05f) out += cursor to length
    return out
}


private data class ArPlaneMeasurement(
    val kind: String,
    val centerX: Float,
    val centerY: Float,
    val centerZ: Float,
    val extentX: Float,
    val extentZ: Float
)

class HouseArScanActivity : ComponentActivity() {
    private var roomName: String = "Stanza"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        roomName = intent.getStringExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME)
            ?.takeIf { it.isNotBlank() } ?: "Stanza"
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = HouseCyan,
                    secondary = Color(0xFF9A7BFF),
                    background = HouseBg,
                    surface = HousePanel,
                    onSurface = Color.White
                )
            ) {
                HouseArScanScreen(
                    roomName = roomName,
                    onBack = { finish() },
                    onSaveEstimate = { measurements -> saveEstimateAndOpenEditor(measurements) }
                )
            }
        }
    }

    private fun saveEstimateAndOpenEditor(measurements: List<ArPlaneMeasurement>): String {
        val floor = measurements.filter { it.kind == "PAVIMENTO" }
            .maxByOrNull { it.extentX * it.extentZ }
            ?: return "Pavimento non rilevato: muovi lentamente il telefono e inquadra il pavimento."

        if (floor.extentX < 2f || floor.extentZ < 2f) {
            return "Il piano è ancora troppo piccolo per stimare la stanza. Continua la scansione."
        }
        if (floor.extentX > 8f || floor.extentZ > 8f) {
            return "La stima supera l'intervallo attuale 2–8 m. Usa l'editor per impostare le dimensioni manualmente."
        }

        return try {
            val previous = HouseProjectRepository.load(filesDir, roomName)
            val estimatedWidth = floor.extentX.coerceIn(2f, 8f)
            val estimatedDepth = floor.extentZ.coerceIn(2f, 8f)
            val draft = previous.copy(
                width = estimatedWidth,
                depth = estimatedDepth,
                openings = normalizeOpenings(previous.openings, estimatedWidth, estimatedDepth),
                scaleConfirmed = false
            )
            HouseProjectRepository.save(filesDir, roomName, draft)

            val planeJson = JSONArray()
            measurements.forEach { p ->
                planeJson.put(
                    JSONObject()
                        .put("kind", p.kind)
                        .put("centerX", p.centerX)
                        .put("centerY", p.centerY)
                        .put("centerZ", p.centerZ)
                        .put("extentX", p.extentX)
                        .put("extentZ", p.extentZ)
                )
            }
            val evidence = JSONObject()
                .put("version", 1)
                .put("roomName", roomName)
                .put("capturedAtEpochMs", System.currentTimeMillis())
                .put("floorWidthMeters", floor.extentX)
                .put("floorDepthMeters", floor.extentZ)
                .put("scaleConfirmed", false)
                .put("trackedPlaneCount", measurements.size)
                .put("planes", planeJson)
            arEvidenceFile(filesDir, roomName).writeText(evidence.toString(2))

            startActivity(
                Intent(this, HouseReconstructionActivity::class.java)
                    .putExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME, roomName)
            )
            finish()
            "Stima AR salvata: verifica le dimensioni nell'editor."
        } catch (e: Exception) {
            "Salvataggio della stima non riuscito: ${e.localizedMessage ?: e.javaClass.simpleName}"
        }
    }
}

@Composable
private fun HouseArScanScreen(
    roomName: String,
    onBack: () -> Unit,
    onSaveEstimate: (List<ArPlaneMeasurement>) -> String
) {
    var trackedPlanes by remember { mutableStateOf<List<ArPlaneMeasurement>>(emptyList()) }
    var sessionReady by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Avvio ARCore: inquadra il pavimento e muovi lentamente il telefono.") }
    val updateCounter = remember { AtomicInteger(0) }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val floor = trackedPlanes.filter { it.kind == "PAVIMENTO" }.maxByOrNull { it.extentX * it.extentZ }
    val wallCount = trackedPlanes.count { it.kind == "PARETE" }
    val floorSize = floor?.let { "${"%.1f".format(it.extentX)} × ${"%.1f".format(it.extentZ)} m" } ?: "in rilevamento"
    val usableFloor = floor != null && floor.extentX >= 2f && floor.extentZ >= 2f &&
        floor.extentX <= 8f && floor.extentZ <= 8f

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        ARSceneView(
            modifier = Modifier.fillMaxSize(),
            planeRenderer = true,
            planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL,
            depthMode = Config.DepthMode.AUTOMATIC,
            sessionConfiguration = { session, config ->
                config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                config.depthMode = if (runCatching { session.isDepthModeSupported(Config.DepthMode.AUTOMATIC) }.getOrDefault(false)) {
                    Config.DepthMode.AUTOMATIC
                } else {
                    Config.DepthMode.DISABLED
                }
            },
            onSessionCreated = {
                sessionReady = true
                status = "ARCore attivo · cerca il pavimento e le pareti."
            },
            onSessionFailed = { exception ->
                sessionReady = false
                status = "ARCore non avviabile: ${exception.localizedMessage ?: exception.javaClass.simpleName}"
            },
            onSessionUpdated = { session, frame ->
                if (updateCounter.incrementAndGet() % 12 == 0) {
                    val snapshot = runCatching {
                        session.getAllTrackables(Plane::class.java)
                            .filter { it.trackingState == TrackingState.TRACKING && it.subsumedBy == null }
                            .mapNotNull { plane ->
                                val kind = when (plane.type) {
                                    Plane.Type.HORIZONTAL_UPWARD_FACING -> "PAVIMENTO"
                                    Plane.Type.VERTICAL -> "PARETE"
                                    else -> null
                                } ?: return@mapNotNull null
                                if (plane.extentX <= 0.05f || plane.extentZ <= 0.05f) return@mapNotNull null
                                ArPlaneMeasurement(
                                    kind = kind,
                                    centerX = plane.centerPose.tx(),
                                    centerY = plane.centerPose.ty(),
                                    centerZ = plane.centerPose.tz(),
                                    extentX = plane.extentX,
                                    extentZ = plane.extentZ
                                )
                            }
                    }.getOrElse { emptyList() }
                    val tracking = frame.camera.trackingState == TrackingState.TRACKING
                    mainHandler.post {
                        trackedPlanes = snapshot
                        status = if (!tracking) {
                            "Tracking in acquisizione: muovi lentamente il telefono e guarda superfici ben illuminate."
                        } else {
                            "Tracking attivo · ${snapshot.count { it.kind == "PAVIMENTO" }} piani pavimento · ${snapshot.count { it.kind == "PARETE" }} pareti candidate."
                        }
                    }
                }
            }
        ) { }

        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(12.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Card(colors = CardDefaults.cardColors(containerColor = HousePanel.copy(alpha = 0.94f))) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("SENTINEL ONE · SCANSIONE AR", color = HouseCyan, fontSize = 11.sp)
                    Text(roomName, color = Color.White, fontSize = 21.sp)
                    Text(status, color = Color.White, fontSize = 12.sp)
                    Text("Piani tracciati: ${trackedPlanes.size} · pareti: $wallCount", color = HouseMuted, fontSize = 11.sp)
                    Text("Estensione pavimento rilevata: $floorSize", color = if (usableFloor) Color(0xFF55E6B1) else Color(0xFFFFC36B), fontSize = 12.sp)
                }
            }
            Card(colors = CardDefaults.cardColors(containerColor = HousePanel.copy(alpha = 0.96f))) {
                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Cammina lentamente attorno alla stanza; ruota il telefono per includere pavimento e tutte le pareti. Mantieni gli angoli nell'inquadratura. La misura è una stima del piano osservato, non una certificazione del perimetro.", color = HouseMuted, fontSize = 11.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = onBack, modifier = Modifier.weight(1f)) { Text("INDIETRO") }
                        Button(
                            onClick = { status = onSaveEstimate(trackedPlanes) },
                            enabled = sessionReady && usableFloor,
                            modifier = Modifier.weight(1.25f),
                            colors = ButtonDefaults.buttonColors(containerColor = HouseCyan, contentColor = Color(0xFF07101A))
                        ) { Text("USA STIMA AR", fontSize = 11.sp) }
                    }
                }
            }
        }
    }
}


private data class HouseProjectSummary(
    val roomName: String,
    val geometry: HouseGeometry,
    val captureCount: Int,
    val hasArEvidence: Boolean
)

class HouseProjectsActivity : ComponentActivity() {
    private var rooms by mutableStateOf<List<HouseProjectSummary>>(emptyList())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        refreshRooms()
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = HouseCyan,
                    secondary = Color(0xFF9A7BFF),
                    background = HouseBg,
                    surface = HousePanel,
                    onSurface = Color.White
                )
            ) {
                HouseProjectsScreen(
                    rooms = rooms,
                    onBack = { finish() },
                    onOpenEditor = { openRoom(it, HouseReconstructionActivity::class.java) },
                    onStartCapture = { openRoom(it, RoomScanActivity::class.java) },
                    onStartAr = { openRoom(it, HouseArScanActivity::class.java) },
                    onNewRoom = {
                        startActivity(
                            Intent(this, RoomScanActivity::class.java)
                                .putExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME, "Nuova stanza")
                        )
                    }
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshRooms()
    }

    private fun openRoom(roomName: String, destination: Class<*>) {
        startActivity(
            Intent(this, destination)
                .putExtra(HouseReconstructionActivity.EXTRA_ROOM_NAME, roomName)
        )
    }

    private fun refreshRooms() {
        val names = linkedSetOf<String>()
        filesDir.listFiles()?.filter { it.isFile }?.forEach { file ->
            when {
                file.name == "sentinel_house_project.json" -> names += "Stanza"
                file.name.startsWith("sentinel_house_project_") && file.name.endsWith(".json") ->
                    names += file.name.removePrefix("sentinel_house_project_").removeSuffix(".json")
                file.name.startsWith("sentinel_ar_scan_") && file.name.endsWith(".json") ->
                    names += file.name.removePrefix("sentinel_ar_scan_").removeSuffix(".json")
            }
        }

        val base = getExternalFilesDir(Environment.DIRECTORY_PICTURES) ?: filesDir
        val scanRoot = File(base, "SENTINEL_ONE_SCAN")
        scanRoot.listFiles()?.filter { it.isDirectory }?.forEach { names += it.name }

        rooms = names.map { normalizedRoomName(it) }
            .distinct()
            .map { room ->
                val roomDir = File(scanRoot, room)
                val captures = roomDir.listFiles()
                    ?.count { it.isFile && it.extension.lowercase() in setOf("jpg", "jpeg", "mp4") }
                    ?: 0
                HouseProjectSummary(
                    roomName = room,
                    geometry = HouseProjectRepository.load(filesDir, room),
                    captureCount = captures,
                    hasArEvidence = arEvidenceFile(filesDir, room).isFile
                )
            }
            .sortedBy { it.roomName.lowercase() }
    }
}

@Composable
private fun HouseProjectsScreen(
    rooms: List<HouseProjectSummary>,
    onBack: () -> Unit,
    onOpenEditor: (String) -> Unit,
    onStartCapture: (String) -> Unit,
    onStartAr: (String) -> Unit,
    onNewRoom: () -> Unit
) {
    Column(
        Modifier.fillMaxSize()
            .background(HouseBg)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
        ) {
            OutlinedButton(onClick = onBack) { Text("INDIETRO") }
            Column(Modifier.weight(1f)) {
                Text("SENTINEL ONE", color = HouseCyan, fontSize = 11.sp)
                Text("Stanze salvate", color = Color.White, fontSize = 22.sp)
            }
        }
        Text(
            "Ogni ambiente mantiene la propria piantina, le acquisizioni e le evidenze AR.",
            color = HouseMuted,
            fontSize = 12.sp
        )
        Button(
            onClick = onNewRoom,
            modifier = Modifier.fillMaxWidth().height(50.dp)
        ) { Text("+ NUOVA STANZA · FOTO / VIDEO") }

        if (rooms.isEmpty()) {
            Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Nessuna stanza salvata", color = Color.White, fontSize = 17.sp)
                    Text(
                        "Avvia una nuova acquisizione, inserisci il nome dell'ambiente e salva almeno una foto oppure una piantina.",
                        color = HouseMuted,
                        fontSize = 12.sp
                    )
                }
            }
        }

        rooms.forEach { room ->
            Card(
                colors = CardDefaults.cardColors(containerColor = HousePanel),
                shape = RoundedCornerShape(16.dp)
            ) {
                Column(
                    Modifier.fillMaxWidth().padding(13.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(room.roomName.replace('_', ' '), color = Color.White, fontSize = 18.sp)
                    Text(
                        "%.1f × %.1f m · %d porte/finestre".format(
                            room.geometry.width,
                            room.geometry.depth,
                            room.geometry.openings.size
                        ),
                        color = HouseCyan,
                        fontSize = 12.sp
                    )
                    Text(
                        "${room.captureCount} foto/video · " + if (room.hasArEvidence) "stima AR disponibile" else "nessuna stima AR salvata",
                        color = HouseMuted,
                        fontSize = 11.sp
                    )
                    Button(
                        onClick = { onOpenEditor(room.roomName) },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("APRI PIANTINA 2D / MODELLO 3D") }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { onStartCapture(room.roomName) },
                            modifier = Modifier.weight(1f)
                        ) { Text("FOTO / VIDEO", fontSize = 10.sp) }
                        OutlinedButton(
                            onClick = { onStartAr(room.roomName) },
                            modifier = Modifier.weight(1f)
                        ) { Text("SCANSIONE AR", fontSize = 10.sp) }
                    }
                }
            }
        }
    }
}
