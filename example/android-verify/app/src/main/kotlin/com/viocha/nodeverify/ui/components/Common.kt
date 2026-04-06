package com.viocha.nodeverify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viocha.nodeverify.model.NodeItem

@Composable
fun CardShell(
    title: String,
    content: @Composable () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFFCF7))
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = Color(0xFF1F1812)
            )
            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider(color = Color(0xFFE7DACB))
            Spacer(modifier = Modifier.height(14.dp))
            content()
        }
    }
}

@Composable
fun KeyValueRow(item: NodeItem) {
    Column {
        Text(
            text = item.label,
            style = MaterialTheme.typography.labelMedium,
            color = Color(0xFF7B6650)
        )
        Spacer(modifier = Modifier.height(2.dp))
        SelectionContainer {
            Text(
                text = item.value,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = if (item.value.length > 60) FontFamily.Monospace else FontFamily.Default
                ),
                color = Color(0xFF231B16),
                lineHeight = 21.sp
            )
        }
    }
}

@Composable
fun BulletLine(text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier
                .padding(top = 8.dp)
                .size(7.dp)
                .clip(CircleShape)
                .background(Color(0xFFD06E3A))
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF2A211A),
            lineHeight = 21.sp
        )
    }
}

@Composable
fun LoadingCard(message: String) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = Color(0xFFF7EFE4)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.5.dp
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFF695747)
            )
        }
    }
}

@Composable
fun BrokenCard(rawOutput: String) {
    CardShell(title = "Unstructured Output") {
        Text(
            text = "The console could not parse the returned payload.",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF665447)
        )
        Spacer(modifier = Modifier.height(12.dp))
        SelectionContainer {
            Text(
                text = rawOutput,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = Color(0xFF372B22)
            )
        }
    }
}
