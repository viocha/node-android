package com.viocha.nodeverify.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFFAA4B20),
    onPrimary = Color(0xFFFFF7F2),
    secondary = Color(0xFF8D6E4A),
    onSecondary = Color(0xFFFFF8F3),
    tertiary = Color(0xFF3D7A67),
    background = Color(0xFFF7F1E8),
    onBackground = Color(0xFF201913),
    surface = Color(0xFFFFFBF5),
    onSurface = Color(0xFF241C16)
)

@Composable
fun NodeVerifyTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content
    )
}
