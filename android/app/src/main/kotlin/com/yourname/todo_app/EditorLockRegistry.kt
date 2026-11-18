package com.yourname.todo_app

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Thread-safe locks for diary editors in this Android application process.
 *
 * Acquiring the same note twice with the same owner is idempotent: it succeeds
 * but does not create a reference count, so one matching [release] clears it.
 */
class EditorLockRegistry {
    private val locks = mutableMapOf<Int, String>()

    @Synchronized
    fun tryAcquire(noteId: Int, ownerId: String): Boolean {
        val currentOwner = locks[noteId]
        if (currentOwner == null || currentOwner == ownerId) {
            locks[noteId] = ownerId
            return true
        }
        return false
    }

    @Synchronized
    fun release(noteId: Int, ownerId: String): Boolean {
        if (locks[noteId] != ownerId) return false
        locks.remove(noteId)
        return true
    }

    @Synchronized
    fun isLocked(noteId: Int): Boolean = locks.containsKey(noteId)

    @Synchronized
    fun getLockedIds(): Set<Int> = locks.keys.toSet()

    @Synchronized
    fun releaseAll(ownerId: String): Int {
        val ids = locks.filterValues { it == ownerId }.keys.toList()
        ids.forEach(locks::remove)
        return ids.size
    }
}

/** The one registry shared by MainActivity and ShareActivity in this process. */
object ProcessEditorLockRegistry {
    private val registry = EditorLockRegistry()

    fun tryAcquire(noteId: Int, ownerId: String) = registry.tryAcquire(noteId, ownerId)
    fun release(noteId: Int, ownerId: String) = registry.release(noteId, ownerId)
    fun isLocked(noteId: Int) = registry.isLocked(noteId)
    fun getLockedIds() = registry.getLockedIds()
    fun releaseAll(ownerId: String) = registry.releaseAll(ownerId)
}

/**
 * A MethodChannel facade for one Flutter engine.
 *
 * It remembers only owners which actually acquired a lock through this engine.
 * Disposing this bridge therefore cannot release another active engine's locks.
 */
class EditorLockChannel(messenger: BinaryMessenger) {
    private val owners = mutableSetOf<String>()
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "newOwner" -> {
                    val ownerId = UUID.randomUUID().toString()
                    owners += ownerId
                    result.success(ownerId)
                }

                "tryAcquire" -> withLockArguments(call, result) { noteId, ownerId ->
                    val acquired = ProcessEditorLockRegistry.tryAcquire(noteId, ownerId)
                    if (acquired) owners += ownerId
                    result.success(acquired)
                }

                "release" -> withLockArguments(call, result) { noteId, ownerId ->
                    result.success(ProcessEditorLockRegistry.release(noteId, ownerId))
                }

                "isLocked" -> {
                    val noteId = call.noteId()
                    if (noteId == null) {
                        result.error("bad_note_id", "Missing or invalid noteId", null)
                    } else {
                        result.success(ProcessEditorLockRegistry.isLocked(noteId))
                    }
                }

                "getLockedIds" -> result.success(ProcessEditorLockRegistry.getLockedIds().sorted())

                "releaseAll" -> {
                    val ownerId = call.ownerId()
                    if (ownerId == null) {
                        result.error("bad_owner_id", "Missing ownerId", null)
                    } else if (!owners.remove(ownerId)) {
                        result.success(0)
                    } else {
                        result.success(ProcessEditorLockRegistry.releaseAll(ownerId))
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        owners.toList().forEach(ProcessEditorLockRegistry::releaseAll)
        owners.clear()
    }

    private fun withLockArguments(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (noteId: Int, ownerId: String) -> Unit,
    ) {
        val noteId = call.noteId()
        val ownerId = call.ownerId()
        if (noteId == null) {
            result.error("bad_note_id", "Missing or invalid noteId", null)
        } else if (ownerId == null) {
            result.error("bad_owner_id", "Missing ownerId", null)
        } else {
            action(noteId, ownerId)
        }
    }

    private fun MethodCall.noteId(): Int? = when (val value = argument<Any>("noteId")) {
        is Int -> value
        is Long -> value.toInt()
        is Number -> value.toInt()
        else -> null
    }?.takeIf { it > 0 }

    private fun MethodCall.ownerId(): String? =
        argument<String>("ownerId")?.takeIf { it.isNotBlank() }

    private companion object {
        const val CHANNEL_NAME = "com.yourname.todo_app/editor_lock"
    }
}
