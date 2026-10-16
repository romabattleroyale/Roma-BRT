package com.sentinelone.nativeapp

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import com.google.android.gms.tasks.Task

private const val SERVICE_ID = "com.sentinelone.nativeapp.camera-link"
private const val PERMISSION_REQUEST = 401

private val Night = Color(0xFF080B13)
private val Panel = Color(0xFF111827)
private val Cyan = Color(0xFF53E5F2)
private val Violet = Color(0xFF9A7BFF)
private val Muted = Color(0xFF9BA8BC)

class MainActivity : ComponentActivity() {
    private lateinit var connections: ConnectionsClient
    private var role by mutableStateOf("monitor")
    private var status by mutableStateOf("Pronto per collegare i dispositivi")
    private var connectedName by mutableStateOf<String?>(null)
    private var discovered by mutableStateOf<List<Pair<String, String>>>(emptyList())
    private var working by mutableStateOf(false)
    private var activeEndpoint: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        connections = Nearby.getConnectionsClient(this)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Cyan,
                    secondary = Violet,
                    background = Night,
                    surface = Panel,
                    onBackground = Color.White,
                    onSurface = Color.White
                )
            ) {
                Dashboard(
                    role = role,
                    status = status,
                    connectedName = connectedName,
                    discovered = discovered,
                    working = working,
                    onRole = { role = it; stopSearching() },
                    onStart = { startPairing() },
                    onConnect = { endpoint -> requestPair(endpoint) },
                    onStop = { stopSearching() }
                )
            }
        }
    }

    private fun requiredPermissions(): Array<String> {
        val result = mutableListOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.NEARBY_WIFI_DEVICES
        )
        if (Build.VERSION.SDK_INT <= 32) {
            result += Manifest.permission.ACCESS_FINE_LOCATION
            if (Build.VERSION.SDK_INT <= 30) {
                result += Manifest.permission.BLUETOOTH
                result += Manifest.permission.BLUETOOTH_ADMIN
            }
        }
        return result.toTypedArray()
    }

    private fun startPairing() {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST)
            status = "Autorizza i dispositivi nelle vicinanze, poi premi di nuovo"
            return
        }

        discovered = emptyList()
        connectedName = null
        activeEndpoint = null
        working = true
        status = if (role == "monitor") "Monitor visibile agli altri telefoni" else "Ricerca del monitor nelle vicinanze…"

        if (role == "monitor") {
            val options = AdvertisingOptions.Builder()
                .setStrategy(Strategy.P2P_POINT_TO_POINT)
                .build()
            connections.startAdvertising(
                "SENTINEL ONE · Monitor",
                SERVICE_ID,
                lifecycleCallback,
                options
            ).addOnFailureListener { fail("Avvio monitor non riuscito: ${it.localizedMessage}") }
        } else {
            val options = DiscoveryOptions.Builder()
                .setStrategy(Strategy.P2P_POINT_TO_POINT)
                .build()
            connections.startDiscovery(SERVICE_ID, discoveryCallback, options)
                .addOnFailureListener { fail("Ricerca non riuscita: ${it.localizedMessage}") }
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
                    connectedName = discovered.firstOrNull { it.first == endpointId }?.second
                        ?: "SENTINEL ONE"
                    status = "Dispositivi collegati"
                    working = false
                    connections.stopDiscovery()
                    connections.stopAdvertising()
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
                status = "Dispositivo disconnesso"
                working = false
            }
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            // The link is established first; live camera payloads are the next implementation layer.
        }
        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) = Unit
    }

    private fun requestPair(endpointId: String) {
        val name = discovered.firstOrNull { it.first == endpointId }?.second ?: "SENTINEL ONE"
        status = "Richiesta di collegamento a $name…"
        connections.requestConnection("SENTINEL ONE · Telecamera", endpointId, lifecycleCallback)
            .addOnFailureListener { fail("Richiesta fallita: ${it.localizedMessage}") }
    }

    private fun stopSearching() {
        if (!::connections.isInitialized) return
        connections.stopDiscovery()
        connections.stopAdvertising()
        working = false
        if (connectedName == null) status = "Ricerca interrotta"
    }

    private fun fail(message: String) {
        runOnUiThread { status = message; working = false }
    }

    override fun onDestroy() {
        stopSearching()
        connections.stopAllEndpoints()
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
    onRole: (String) -> Unit,
    onStart: () -> Unit,
    onConnect: (String) -> Unit,
    onStop: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFF10182A), Night, Color(0xFF070910))))
    ) {
        Column(
            modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
                .padding(horizontal = 22.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(48.dp).background(
                        Brush.linearGradient(listOf(Cyan, Violet)),
                        RoundedCornerShape(15.dp)
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Text("S", color = Night, fontSize = 27.sp, fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.width(13.dp))
                Column(Modifier.weight(1f)) {
                    Text("SENTINEL ONE", fontSize = 19.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.6.sp)
                    Text("SMART SECURITY", fontSize = 10.sp, color = Muted, letterSpacing = 2.2.sp)
                }
                Text("NATIVE", color = Cyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("La tua casa.", fontSize = 31.sp, fontWeight = FontWeight.Bold)
                Text("Sotto controllo.", fontSize = 31.sp, fontWeight = FontWeight.Bold, color = Cyan)
                Text("Collega due telefoni senza configurazioni manuali.", color = Muted, fontSize = 14.sp)
            }

            Card(
                colors = CardDefaults.cardColors(containerColor = Panel.copy(alpha = 0.96f)),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(15.dp)) {
                    Text("CONFIGURA QUESTO TELEFONO", color = Muted, fontSize = 11.sp, letterSpacing = 1.3.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        RoleCard("TELECAMERA", "Invia il video", role == "camera", Modifier.weight(1f)) { onRole("camera") }
                        RoleCard("MONITOR", "Riceve il video", role == "monitor", Modifier.weight(1f)) { onRole("monitor") }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.size(9.dp).background(if (connectedName != null) Cyan else Violet, RoundedCornerShape(50)))
                        Column(Modifier.weight(1f)) {
                            Text(if (connectedName != null) "COLLEGAMENTO ATTIVO" else "STATO CONNESSIONE", fontSize = 11.sp, color = Muted)
                            Text(connectedName ?: status, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                    Button(
                        onClick = onStart,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(15.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Cyan, contentColor = Night)
                    ) {
                        Text(if (working) "RICERCA IN CORSO…" else if (role == "monitor") "RENDi VISIBILE IL MONITOR" else "CERCA IL MONITOR", fontWeight = FontWeight.Bold)
                    }
                    if (working || connectedName != null) {
                        OutlinedButton(onClick = onStop, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) {
                            Text("Interrompi ricerca")
                        }
                    }
                }
            }

            if (role == "camera") {
                Text("DISPOSITIVI TROVATI", color = Muted, fontSize = 11.sp, letterSpacing = 1.4.sp)
                if (discovered.isEmpty()) {
                    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF0E1420)), shape = RoundedCornerShape(18.dp)) {
                        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("⌕", color = Cyan, fontSize = 25.sp)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("Nessun monitor ancora", fontWeight = FontWeight.SemiBold)
                                Text("Apri SENTINEL ONE sull'altro telefono e rendilo visibile.", color = Muted, fontSize = 12.sp)
                            }
                        }
                    }
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(discovered, key = { it.first }) { item ->
                            Card(colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(16.dp)) {
                                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(item.second, fontWeight = FontWeight.SemiBold)
                                        Text("Disponibile nelle vicinanze", color = Muted, fontSize = 12.sp)
                                    }
                                    Button(onClick = { onConnect(item.first) }) { Text("Collega") }
                                }
                            }
                        }
                    }
                }
            } else {
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF0E1420)), shape = RoundedCornerShape(18.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text("PRIVACY FIRST", color = Cyan, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
                        Text("Il nuovo collegamento usa la comunicazione diretta tra dispositivi nelle vicinanze. Non richiede un server Render per la fase di abbinamento.", fontSize = 13.sp, color = Muted)
                    }
                }
            }
            Spacer(Modifier.weight(1f, fill = false))
            Text("PROTOTIPO NATIVO ANDROID • ABBINAMENTO DIRETTO", color = Color(0xFF68758B), fontSize = 9.sp, letterSpacing = 1.sp)
        }
    }
}

@Composable
private fun RoleCard(title: String, subtitle: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = modifier.height(82.dp),
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
