package com.sentinelone.nativeapp

import android.os.Bundle
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import kotlin.math.min

private val HouseBg = Color(0xFF080B13)
private val HousePanel = Color(0xFF111827)
private val HouseCyan = Color(0xFF53E5F2)
private val HouseMuted = Color(0xFF9BA8BC)

data class HouseOpening(val id: String = UUID.randomUUID().toString(), val wall: String, val type: String, val offset: Float, val width: Float, val height: Float)
data class HouseGeometry(val width: Float = 5f, val depth: Float = 4f, val height: Float = 2.7f, val openings: List<HouseOpening> = emptyList(), val scaleConfirmed: Boolean = false)

private object HouseProjectRepository {
    private const val FILE = "sentinel_house_project.json"
    fun load(dir: File): HouseGeometry = runCatching {
        val j = JSONObject(File(dir, FILE).readText())
        val a = j.optJSONArray("openings") ?: JSONArray()
        HouseGeometry(j.optDouble("width", 5.0).toFloat().coerceIn(2f, 8f), j.optDouble("depth", 4.0).toFloat().coerceIn(2f, 8f), j.optDouble("height", 2.7).toFloat().coerceIn(2.2f, 4f), (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            HouseOpening(o.optString("id", UUID.randomUUID().toString()), o.optString("wall", "Nord"), o.optString("type", "Porta"), o.optDouble("offset", .5).toFloat(), o.optDouble("width", .9).toFloat(), o.optDouble("height", 2.05).toFloat())
        }, j.optBoolean("scaleConfirmed", false))
    }.getOrDefault(HouseGeometry())
    fun save(dir: File, g: HouseGeometry) {
        val a = JSONArray()
        g.openings.forEach { o -> a.put(JSONObject().put("id", o.id).put("wall", o.wall).put("type", o.type).put("offset", o.offset).put("width", o.width).put("height", o.height)) }
        File(dir, FILE).writeText(JSONObject().put("version", 1).put("width", g.width).put("depth", g.depth).put("height", g.height).put("scaleConfirmed", g.scaleConfirmed).put("openings", a).toString(2))
    }
}

class HouseReconstructionActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val initial = HouseProjectRepository.load(filesDir)
        setContent { MaterialTheme(colorScheme = darkColorScheme(primary = HouseCyan, secondary = Color(0xFF9A7BFF), background = HouseBg, surface = HousePanel, onSurface = Color.White)) {
            HouseEditor(initial, { HouseProjectRepository.save(filesDir, it) }, { finish() })
        } }
    }
}

@Composable
private fun HouseEditor(initial: HouseGeometry, save: (HouseGeometry) -> Unit, back: () -> Unit) {
    var g by remember { mutableStateOf(initial) }
    var wall by remember { mutableStateOf("Nord") }
    var type by remember { mutableStateOf("Porta") }
    var message by remember { mutableStateOf("Progetto pronto") }
    Column(Modifier.fillMaxSize().background(HouseBg).statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { OutlinedButton(onClick = back) { Text("INDIETRO") }; Column { Text("SENTINEL ONE", color = HouseCyan); Text("Ricostruzione 2D/3D", color = Color.White, fontSize = 21.sp) } }
        Card(colors = CardDefaults.cardColors(containerColor = HousePanel)) {
            Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("PIANTINA 2D · METRI", color = HouseCyan)
                FloorPlan(g, Modifier.fillMaxWidth().height(220.dp))
                Text("Larghezza: %.1f m".format(g.width), color = Color.White)
                Slider(g.width, { g = g.copy(width = it, scaleConfirmed = false) }, valueRange = 2f..8f)
                Text("Profondità: %.1f m".format(g.depth), color = Color.White)
                Slider(g.depth, { g = g.copy(depth = it, scaleConfirmed = false) }, valueRange = 2f..8f)
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
                        if (len > w + .3f) {
                            g = g.copy(openings = g.openings + HouseOpening(wall = wall, type = type, offset = (len - w) / 2f, width = w, height = if (type == "Porta") 2.05f else 1.2f))
                            message = type + " aggiunta"
                        } else message = "Parete troppo corta"
                    }) { Text("AGGIUNGI") }
                }
                g.openings.forEach { o ->
                    val wallLength = if (o.wall == "Nord" || o.wall == "Sud") g.width else g.depth
                    val maxWidth = (wallLength - 0.2f).coerceAtLeast(0.5f)
                    val safeWidth = o.width.coerceIn(0.5f, maxWidth)
                    val safeOffset = o.offset.coerceIn(0f, (wallLength - safeWidth).coerceAtLeast(0f))
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(o.type + " · " + o.wall + " · %.1f m".format(safeWidth), Modifier.weight(1f), color = Color.White, fontSize = 12.sp)
                            TextButton(onClick = { g = g.copy(openings = g.openings.filterNot { it.id == o.id }) }) { Text("RIMUOVI") }
                        }
                        Text("Posizione sulla parete: %.1f m".format(safeOffset), color = HouseMuted, fontSize = 10.sp)
                        Slider(value = safeOffset, onValueChange = { value ->
                            g = g.copy(openings = g.openings.map { item ->
                                if (item.id == o.id) item.copy(offset = value.coerceIn(0f, (wallLength - safeWidth).coerceAtLeast(0f))) else item
                            })
                        }, valueRange = 0f..(wallLength - safeWidth).coerceAtLeast(0.01f))
                        Text("Larghezza: %.1f m".format(safeWidth), color = HouseMuted, fontSize = 10.sp)
                        Slider(value = safeWidth, onValueChange = { value ->
                            g = g.copy(openings = g.openings.map { item ->
                                if (item.id == o.id) item.copy(width = value, offset = item.offset.coerceIn(0f, (wallLength - value).coerceAtLeast(0f))) else item
                            })
                        }, valueRange = 0.5f..maxWidth)
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
        Button(onClick = { save(g); message = "Progetto salvato sul dispositivo" }, modifier = Modifier.fillMaxWidth()) { Text("SALVA PROGETTO 2D/3D") }
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
                    val openingHeight = if (o.type=="Porta") 2.05f else o.height
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
                    val openingHeight = if (o.type=="Porta") 2.05f else o.height
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
