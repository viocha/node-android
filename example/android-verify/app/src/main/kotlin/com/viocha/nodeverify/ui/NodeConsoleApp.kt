package com.viocha.nodeverify.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.viocha.nodeverify.model.ConsoleDestination
import com.viocha.nodeverify.model.ReportUiState
import com.viocha.nodeverify.model.parseReport
import com.viocha.nodeverify.ui.components.BrokenCard
import com.viocha.nodeverify.ui.components.LoadingCard
import com.viocha.nodeverify.ui.screens.ChecksScreen
import com.viocha.nodeverify.ui.screens.OverviewScreen
import com.viocha.nodeverify.ui.screens.PlaygroundScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NodeConsoleApp(
    runNodeCommand: (String, String) -> String
) {
    var selectedDestination by rememberSaveable { mutableStateOf(ConsoleDestination.Overview.name) }
    val reportState by produceState<ReportUiState>(initialValue = ReportUiState.Loading) {
        value = ReportUiState.Loading
        val payload = withContext(Dispatchers.IO) {
            runNodeCommand("report", "{}")
        }
        value = parseReport(payload)?.let { ReportUiState.Ready(it) }
            ?: ReportUiState.Broken(payload)
    }

    val backgroundBrush = remember {
        Brush.verticalGradient(
            colors = listOf(
                Color(0xFFF2E4D4),
                Color(0xFFF8F2E9),
                Color(0xFFF4EEE5)
            )
        )
    }

    val currentDestination = ConsoleDestination.valueOf(selectedDestination)

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        text = "Node Android Console",
                        fontWeight = FontWeight.SemiBold
                    )
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = Color(0xFFF7F0E6)
                )
            )
        },
        bottomBar = {
            NavigationBar(
                containerColor = Color(0xFFFFFBF4)
            ) {
                val items = listOf(
                    ConsoleDestination.Overview to Icons.Filled.Dashboard,
                    ConsoleDestination.Playground to Icons.Filled.PlayArrow
                )
                items.forEach { (destination, icon) ->
                    NavigationBarItem(
                        selected = currentDestination == destination,
                        onClick = { selectedDestination = destination.name },
                        icon = { Icon(icon, contentDescription = destination.label) },
                        label = { Text(destination.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(backgroundBrush)
                .padding(innerPadding)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 16.dp),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(16.dp)
            ) {
                when (currentDestination) {
                    ConsoleDestination.Overview -> {
                        when (val state = reportState) {
                            ReportUiState.Loading -> item { LoadingCard("Waiting for Node to build the verification report.") }
                            is ReportUiState.Broken -> item { BrokenCard(state.rawOutput) }
                            is ReportUiState.Ready -> {
                                item { OverviewScreen(state.report) }
                                item { ChecksScreen(state.report.checks) }
                            }
                        }
                    }

                    ConsoleDestination.Playground -> {
                        item {
                            PlaygroundScreen(runNodeCommand = runNodeCommand)
                        }
                    }
                }
            }
        }
    }
}
