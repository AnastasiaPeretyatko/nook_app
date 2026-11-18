package com.yourname.todo_app

import android.content.Context
import android.content.SharedPreferences
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.UUID

/**
 * Durable, arrival-ordered inbox for native share intents.
 *
 * This deliberately has no knowledge of which event the UI makes active. The
 * activity/channel integration chooses an event later; this class only keeps
 * every accepted event until it is acknowledged or discarded.
 */
class PendingShareEventStore private constructor(
    private val storage: Storage,
    private val nowMillis: () -> Long,
    @Suppress("UNUSED_PARAMETER") private val constructorMarker: Unit,
) {
    constructor(context: Context) : this(
        SharedPreferencesStorage(
            context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE),
        ),
        System::currentTimeMillis,
        Unit,
    )

    internal constructor(storage: Storage, nowMillis: () -> Long = System::currentTimeMillis) :
        this(storage, nowMillis, Unit)

    data class Event(val id: String, val text: String, val receivedAt: Long)

    sealed class Result<out T> {
        data class Success<T>(val value: T) : Result<T>()
        data class Failure(val reason: FailureReason) : Result<Nothing>()
    }

    enum class FailureReason {
        EMPTY_TEXT,
        QUEUE_FULL,
        PAYLOAD_LIMIT_EXCEEDED,
        PERSISTENCE_FAILED,
        MALFORMED_DATA,
        UNSUPPORTED_FORMAT,
    }

    /** Writes a new event only after the durable commit succeeds. */
    fun enqueue(text: String): Result<Event> = synchronized(processLock) {
        val events = loadAndPrune() ?: return@synchronized lastFailure!!
        if (text.isEmpty()) return@synchronized Result.Failure(FailureReason.EMPTY_TEXT)
        if (events.size >= MAX_PENDING_EVENTS) return@synchronized Result.Failure(FailureReason.QUEUE_FULL)
        val textBytes = text.toByteArray(StandardCharsets.UTF_8).size.toLong()
        if (payloadBytes(events) + textBytes > MAX_TEXT_PAYLOAD_BYTES) {
            return@synchronized Result.Failure(FailureReason.PAYLOAD_LIMIT_EXCEEDED)
        }

        val event = Event(UUID.randomUUID().toString(), text, nowMillis())
        val updated = events + event
        if (!write(updated)) return@synchronized Result.Failure(FailureReason.PERSISTENCE_FAILED)
        Result.Success(event)
    }

    /** Returns all pending events in arrival order, after durable expiry pruning. */
    fun snapshot(): Result<List<Event>> = synchronized(processLock) {
        val events = loadAndPrune() ?: return@synchronized lastFailure!!
        Result.Success(events)
    }

    /** Looks up a pending event by stable ID without implying it is the active UI event. */
    fun get(id: String): Result<Event?> = synchronized(processLock) {
        val events = loadAndPrune() ?: return@synchronized lastFailure!!
        Result.Success(events.firstOrNull { it.id == id })
    }

    /** Removes a processed event. A missing event is a successful idempotent no-op. */
    fun acknowledge(id: String): Result<Boolean> = remove(id)

    /** Removes an unwanted event. A missing event is a successful idempotent no-op. */
    fun discard(id: String): Result<Boolean> = remove(id)

    /** Prunes events older than seven days and returns the number removed. */
    fun pruneExpired(): Result<Int> = synchronized(processLock) {
        val encoded = storage.read()
        val events = decode(encoded) ?: return@synchronized lastFailure!!
        val retained = events.filterNot(::isExpired)
        if (retained.size == events.size) return@synchronized Result.Success(0)
        if (!write(retained)) return@synchronized Result.Failure(FailureReason.PERSISTENCE_FAILED)
        Result.Success(events.size - retained.size)
    }

    private fun remove(id: String): Result<Boolean> = synchronized(processLock) {
        val events = loadAndPrune() ?: return@synchronized lastFailure!!
        val updated = events.filterNot { it.id == id }
        if (updated.size == events.size) return@synchronized Result.Success(false)
        if (!write(updated)) return@synchronized Result.Failure(FailureReason.PERSISTENCE_FAILED)
        Result.Success(true)
    }

    /** Returns null after setting [lastFailure] if decoding or durable pruning fails. */
    private fun loadAndPrune(): List<Event>? {
        val events = decode(storage.read()) ?: return null
        val retained = events.filterNot(::isExpired)
        if (retained.size != events.size && !write(retained)) {
            lastFailure = Result.Failure(FailureReason.PERSISTENCE_FAILED)
            return null
        }
        return retained
    }

    private fun isExpired(event: Event): Boolean = nowMillis() - event.receivedAt > RETENTION_MILLIS

    private fun write(events: List<Event>): Boolean = storage.write(encode(events))

    private fun decode(serialized: String?): List<Event>? {
        lastFailure = null
        if (serialized == null) return emptyList()
        val lines = serialized.split('\n')
        if (lines.firstOrNull() != FORMAT_HEADER) {
            lastFailure = Result.Failure(FailureReason.UNSUPPORTED_FORMAT)
            return null
        }
        if (lines.lastOrNull() != "") {
            lastFailure = Result.Failure(FailureReason.MALFORMED_DATA)
            return null
        }
        val events = ArrayList<Event>(lines.size - 2)
        for (line in lines.drop(1).dropLast(1)) {
            val fields = line.split('\t')
            if (fields.size != 3) return malformed()
            val id = try { UUID.fromString(fields[0]).toString() } catch (_: IllegalArgumentException) { return malformed() }
            val receivedAt = fields[1].toLongOrNull()?.takeIf { it >= 0 } ?: return malformed()
            val text = decodeUtf8(fields[2]) ?: return malformed()
            events += Event(id, text, receivedAt)
        }
        if (
            events.size > MAX_PENDING_EVENTS ||
                events.map { it.id }.toSet().size != events.size ||
                payloadBytes(events) > MAX_TEXT_PAYLOAD_BYTES
        ) return malformed()
        return events
    }

    private fun malformed(): List<Event>? {
        lastFailure = Result.Failure(FailureReason.MALFORMED_DATA)
        return null
    }

    private fun decodeUtf8(encoded: String): String? = try {
        val bytes = Base64.getUrlDecoder().decode(encoded)
        StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    } catch (_: IllegalArgumentException) {
        null
    } catch (_: CharacterCodingException) {
        null
    }

    private fun encode(events: List<Event>): String = buildString {
        append(FORMAT_HEADER).append('\n')
        events.forEach { event ->
            append(event.id).append('\t')
            append(event.receivedAt).append('\t')
            append(Base64.getUrlEncoder().withoutPadding().encodeToString(event.text.toByteArray(StandardCharsets.UTF_8)))
            append('\n')
        }
    }

    private fun payloadBytes(events: List<Event>): Long =
        events.sumOf { it.text.toByteArray(StandardCharsets.UTF_8).size.toLong() }

    internal interface Storage {
        fun read(): String?
        fun write(value: String): Boolean
    }

    private class SharedPreferencesStorage(private val preferences: SharedPreferences) : Storage {
        override fun read(): String? = preferences.getString(EVENTS_KEY, null)

        // commit() intentionally blocks: an event must not be exposed before it is durable.
        override fun write(value: String): Boolean = preferences.edit().putString(EVENTS_KEY, value).commit()
    }

    private var lastFailure: Result.Failure? = null

    companion object {
        const val MAX_PENDING_EVENTS = 20
        const val MAX_TEXT_PAYLOAD_BYTES = 256 * 1024
        const val RETENTION_MILLIS = 7L * 24 * 60 * 60 * 1000

        private const val PREFERENCES_NAME = "pending_share_events"
        private const val EVENTS_KEY = "events"
        private const val FORMAT_HEADER = "pending-share-events:v1"
        private val processLock = Any()
    }
}
