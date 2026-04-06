package com.viocha.nextshell.runtime

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

data class NextLaunchResult(
    val status: String,
    val url: String,
    val detail: String,
    val proxyUrl: String
)

object NextBundleInstaller {
    private const val AssetZipName = "nextjs-app.zip"
    private const val AssetVersionName = "nextjs-app.version"

    suspend fun prepare(context: Context): File = withContext(Dispatchers.IO) {
        val root = File(context.filesDir, "nextjs-shell")
        val installDir = File(root, "runtime")
        val versionFile = File(root, "version.txt")
        val targetVersion = context.assets.open(AssetVersionName).bufferedReader().use { it.readText().trim() }
        val currentVersion = versionFile.takeIf { it.exists() }?.readText()?.trim()

        if (currentVersion != targetVersion || !File(installDir, "server.js").exists()) {
            root.deleteRecursively()
            installDir.mkdirs()
            unzipAsset(context, AssetZipName, installDir)
            versionFile.writeText(targetVersion)
        }

        installDir
    }

    private fun unzipAsset(context: Context, assetName: String, targetDir: File) {
        context.assets.open(assetName).use { input ->
            ZipInputStream(input).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    val outFile = File(targetDir, entry.name)
                    if (entry.isDirectory) {
                        outFile.mkdirs()
                    } else {
                        outFile.parentFile?.mkdirs()
                        FileOutputStream(outFile).use { output ->
                            zip.copyTo(output)
                        }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
        }
    }
}

fun parseLaunchResult(raw: String): NextLaunchResult? {
    val root = runCatching { JSONObject(raw) }.getOrNull() ?: return null
    return NextLaunchResult(
        status = root.optString("status"),
        url = root.optString("url"),
        detail = root.optString("detail"),
        proxyUrl = root.optString("proxy_url").ifBlank {
            root.optString("upstream_url")
        }
    )
}
