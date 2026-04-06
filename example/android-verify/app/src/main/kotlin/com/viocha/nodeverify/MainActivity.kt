package com.viocha.nodeverify

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import com.viocha.nodeverify.ui.NodeConsoleApp
import com.viocha.nodeverify.ui.theme.NodeVerifyTheme

class MainActivity : ComponentActivity() {
    companion object {
        init {
            System.loadLibrary("c++_shared")
            System.loadLibrary("nodeverify")
        }

        @JvmStatic
        private external fun runNodeCommand(
            mode: String,
            payload: String,
            filesDir: String,
            cacheDir: String
        ): String
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { false },
            navigationBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { false }
        )
        setContent {
            NodeVerifyTheme {
                NodeConsoleApp(
                    runNodeCommand = { mode, payload ->
                        runNodeCommand(mode, payload, filesDir.absolutePath, cacheDir.absolutePath)
                    }
                )
            }
        }
    }
}
