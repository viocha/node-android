package com.viocha.nextshell.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFFB14F24),
    onPrimary = Color(0xFFFFF8F5),
    secondary = Color(0xFF3B6F67),
    onSecondary = Color(0xFFF5FFFC),
    background = Color(0xFFF5EFE5),
    onBackground = Color(0xFF241A11),
    surface = Color(0xFFFFFBF6),
    onSurface = Color(0xFF21170F)
)

@Composable
fun NextShellTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content
    )
}
