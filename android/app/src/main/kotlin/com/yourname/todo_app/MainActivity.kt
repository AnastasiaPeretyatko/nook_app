package com.yourname.todo_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pendingSharedText = ArrayDeque<String>()
    private var sharedContentChannel: MethodChannel? = null
    private var editorLockChannel: EditorLockChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Queue before Flutter configures its engine: Dart can consume the
        // initial share as soon as its MethodChannel handler is ready.
        enqueueSharedText(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        editorLockChannel = EditorLockChannel(flutterEngine.dartExecutor.binaryMessenger)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_CONTENT_CHANNEL,
        )
        sharedContentChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                TAKE_PENDING_SHARED_TEXT -> {
                    val texts = pendingSharedText.toList()
                    pendingSharedText.clear()
                    result.success(texts)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        editorLockChannel?.dispose()
        editorLockChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueSharedText(intent)
    }

    private fun enqueueSharedText(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != MIME_TEXT_PLAIN) {
            return
        }

        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (!text.isNullOrEmpty()) {
            pendingSharedText.addLast(text)
            sharedContentChannel?.invokeMethod(SHARED_TEXT_AVAILABLE, null)
        }
    }

    private companion object {
        const val SHARED_CONTENT_CHANNEL = "com.yourname.todo_app/shared_content"
        const val TAKE_PENDING_SHARED_TEXT = "takePendingSharedText"
        const val SHARED_TEXT_AVAILABLE = "sharedTextAvailable"
        const val MIME_TEXT_PLAIN = "text/plain"
    }
}
