package com.viocha.nextshell

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.viocha.nextshell.ui.NextShellApp
import com.viocha.nextshell.ui.theme.NextShellTheme

class MainActivity : ComponentActivity() {
    companion object {
        init {
            System.loadLibrary("c++_shared")
            System.loadLibrary("nextshell")
        }

        @JvmStatic
        private external fun startNextServer(
            appDir: String,
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
            NextShellTheme {
                NextShellApp(
                    startNextServer = { appDir ->
                        startNextServer(appDir, cacheDir.absolutePath)
                    }
                )
            }
        }
    }
}
