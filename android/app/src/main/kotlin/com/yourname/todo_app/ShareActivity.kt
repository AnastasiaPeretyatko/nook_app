package com.yourname.todo_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * A short-lived native shell for Android's plain-text share target.
 *
 * It intentionally owns no Flutter engine: rendering the compact share UI is
 * Task 2. Keeping the received [Intent] in this Activity lets that task bridge
 * cold, warm, and repeated shares without waking MainActivity or MyApp.
 */
class ShareActivity : FlutterActivity() {
    private val pending = ArrayDeque<Event>()
    private var channel: MethodChannel? = null
    private var editorLockChannel: EditorLockChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        restore(savedInstanceState)
        enqueue(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (enqueue(intent)) channel?.invokeMethod("eventsAvailable", null)
    }

    override fun onSaveInstanceState(out: Bundle) { super.onSaveInstanceState(out); out.putStringArrayList("ids", ArrayList(pending.map { it.id })); out.putStringArrayList("texts", ArrayList(pending.map { it.text })) }
    override fun provideFlutterEngine(context: Context) = FlutterEngine(context)
    override fun getBackgroundMode() = FlutterActivityLaunchConfigs.BackgroundMode.transparent
    override fun getDartEntrypointFunctionName() = "shareMain"
    override fun getDartEntrypointLibraryUri() = "package:todo_app/share_to_nook/compact_share.dart"
    override fun shouldDestroyEngineWithHost() = true
    override fun configureFlutterEngine(engine: FlutterEngine) { super.configureFlutterEngine(engine); editorLockChannel = EditorLockChannel(engine.dartExecutor.binaryMessenger); channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.yourname.todo_app/compact_share").also { bridge -> bridge.setMethodCallHandler { call, result -> when (call.method) { "takePending" -> result.success(pending.map { mapOf("id" to it.id, "text" to it.text) }); "acknowledge" -> call.argument<String>("id")?.let { id -> pending.removeAll { it.id == id }; result.success(null) } ?: result.error("bad_event", "Missing id", null); else -> result.notImplemented() } } } }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) { editorLockChannel?.dispose(); editorLockChannel = null; channel?.setMethodCallHandler(null); channel = null; super.cleanUpFlutterEngine(engine) }

    private fun enqueue(intent: Intent?): Boolean { if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return false; val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.takeIf { it.isNotBlank() } ?: return false; pending.addLast(Event(UUID.randomUUID().toString(), text)); return true }
    private fun restore(state: Bundle?) { val ids = state?.getStringArrayList("ids") ?: return; val texts = state.getStringArrayList("texts") ?: return; for (i in 0 until minOf(ids.size, texts.size)) pending.addLast(Event(ids[i], texts[i])) }
    private data class Event(val id: String, val text: String)
}
