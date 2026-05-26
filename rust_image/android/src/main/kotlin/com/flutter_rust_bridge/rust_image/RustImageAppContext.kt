package com.flutter_rust_bridge.rust_image

import android.content.Context

/** Application context for MediaPipe Tasks (set from [RustImagePlugin]). */
object RustImageAppContext {
    @Volatile
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun get(): Context =
        appContext ?: throw IllegalStateException("RustImagePlugin not attached")
}
