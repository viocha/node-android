package com.viocha.nodeverify.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.viocha.nodeverify.model.NodeCheck
import com.viocha.nodeverify.model.NodeReport
import com.viocha.nodeverify.ui.components.BulletLine
import com.viocha.nodeverify.ui.components.CardShell

@Composable
fun OverviewScreen(report: NodeReport) {
    val visibleStats = report.stats.filterNot { it.label == "ICU" || it.label == "Proof" }

    CardShell(title = "Overview") {
        visibleStats.chunked(2).forEachIndexed { rowIndex, rowStats ->
            if (rowIndex > 0) {
                Spacer(modifier = Modifier.height(10.dp))
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                StatCard(
                    stat = rowStats.first(),
                    modifier = Modifier.weight(1f)
                )
                if (rowStats.size > 1) {
                    StatCard(
                        stat = rowStats[1],
                        modifier = Modifier.weight(1f)
                    )
                } else {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Highlights",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(10.dp))
        report.highlights.forEach { BulletLine(it) }
    }
}

@Composable
private fun StatCard(
    stat: com.viocha.nodeverify.model.NodeStat,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(18.dp),
        color = Color(0xFFF4EADF)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 12.dp)
        ) {
            Text(
                text = stat.label,
                style = MaterialTheme.typography.labelMedium,
                color = Color(0xFF77624D)
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = stat.value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun ChecksScreen(checks: List<NodeCheck>) {
    val passed = checks.count { it.ok }
    val progress = if (checks.isEmpty()) 0f else passed.toFloat() / checks.size.toFloat()

    CardShell(title = "Verification Matrix") {
        Text(
            text = "$passed of ${checks.size} checks passed",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF6A5848)
        )
        Spacer(modifier = Modifier.height(12.dp))
        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier.fillMaxWidth(),
            color = if (progress >= 1f) Color(0xFF2E8D5B) else Color(0xFFB17118),
            trackColor = Color(0xFFE8DDD0)
        )
        Spacer(modifier = Modifier.height(14.dp))
        checks.forEachIndexed { index, check ->
            if (index > 0) Spacer(modifier = Modifier.height(10.dp))
            androidx.compose.foundation.layout.Row(
                verticalAlignment = androidx.compose.ui.Alignment.Top
            ) {
                androidx.compose.foundation.layout.Box(
                    modifier = Modifier
                        .padding(top = 6.dp)
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(if (check.ok) Color(0xFF2E8D5B) else Color(0xFFC24738))
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = check.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = check.detail,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color(0xFF655344)
                    )
                }
            }
        }
    }
}
