package com.yourname.todo_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private val <T> PendingShareEventStore.Result<T>.value: T
    get() = when (this) {
        is PendingShareEventStore.Result.Success -> value
        is PendingShareEventStore.Result.Failure -> throw AssertionError("Expected a successful store result, got $this")
    }

class PendingShareEventStoreTest {
    @Test
    fun `first enqueue persists an event`() {
        val storage = FakeStorage()
        val store = store(storage)

        val event = store.enqueue("first").value

        assertEquals(listOf(event), store.snapshot().value)
        assertTrue(requireNotNull(storage.value).startsWith("pending-share-events:v1\n"))
    }

    @Test
    fun `ids remain stable when store is reopened`() {
        val storage = FakeStorage()
        val event = store(storage).enqueue("survives").value

        assertEquals(event, store(storage).get(event.id).value)
    }

    @Test
    fun `identical text shares have distinct ids`() {
        val store = store(FakeStorage())
        val first = store.enqueue("same").value
        val second = store.enqueue("same").value

        assertNotEquals(first.id, second.id)
        assertEquals(listOf(first, second), store.snapshot().value)
    }

    @Test
    fun `snapshot retains arrival order`() {
        val store = store(FakeStorage())
        val first = store.enqueue("one").value
        val second = store.enqueue("two").value

        assertEquals(listOf(first.id, second.id), store.snapshot().value.map { it.id })
    }

    @Test
    fun `acknowledge and discard remove only their event`() {
        val store = store(FakeStorage())
        val acknowledged = store.enqueue("ack").value
        val discarded = store.enqueue("discard").value

        assertTrue(store.acknowledge(acknowledged.id).value)
        assertTrue(store.discard(discarded.id).value)
        assertTrue(store.snapshot().value.isEmpty())
    }

    @Test
    fun `acknowledge and discard are idempotent`() {
        val store = store(FakeStorage())
        val event = store.enqueue("once").value

        assertTrue(store.acknowledge(event.id).value)
        assertFalse(store.acknowledge(event.id).value)
        assertFalse(store.discard(event.id).value)
    }

    @Test
    fun `rejects an event once maximum queue size is reached`() {
        val store = store(FakeStorage())
        repeat(PendingShareEventStore.MAX_PENDING_EVENTS) { store.enqueue("event-$it") }

        val result = store.enqueue("overflow")

        assertTrue(result is PendingShareEventStore.Result.Failure)
        assertEquals(PendingShareEventStore.FailureReason.QUEUE_FULL, (result as PendingShareEventStore.Result.Failure).reason)
    }

    @Test
    fun `rejects an event that exceeds the total payload limit`() {
        val store = store(FakeStorage())
        val oversized = "a".repeat(PendingShareEventStore.MAX_TEXT_PAYLOAD_BYTES + 1)

        val result = store.enqueue(oversized)

        assertTrue(result is PendingShareEventStore.Result.Failure)
        assertEquals(PendingShareEventStore.FailureReason.PAYLOAD_LIMIT_EXCEEDED, (result as PendingShareEventStore.Result.Failure).reason)
    }

    @Test
    fun `expired events are pruned before accepting a new event`() {
        val storage = FakeStorage()
        val now = 1_000_000_000L
        val initial = store(storage, now)
        val expired = initial.enqueue("old").value

        val reopened = store(storage, now + PendingShareEventStore.RETENTION_MILLIS + 1)
        val fresh = reopened.enqueue("new").value

        assertEquals(listOf(fresh), reopened.snapshot().value)
        assertEquals(null, reopened.get(expired.id).value)
    }

    @Test
    fun `explicit expiration pruning returns the number removed`() {
        val storage = FakeStorage()
        val now = 1_000_000_000L
        store(storage, now).enqueue("old")
        val reopened = store(storage, now + PendingShareEventStore.RETENTION_MILLIS + 1)

        assertEquals(1, reopened.pruneExpired().value)
        assertTrue(reopened.snapshot().value.isEmpty())
    }

    @Test
    fun `commit failure leaves enqueue unsuccessful and unexposed`() {
        val storage = FakeStorage(commitSucceeds = false)
        val store = store(storage)

        val result = store.enqueue("not durable")

        assertTrue(result is PendingShareEventStore.Result.Failure)
        assertEquals(PendingShareEventStore.FailureReason.PERSISTENCE_FAILED, (result as PendingShareEventStore.Result.Failure).reason)
        assertTrue(store.snapshot().value.isEmpty())
    }

    @Test
    fun `malformed persisted data is surfaced without clearing it`() {
        val malformed = "pending-share-events:v1\nnot-an-event\n"
        val storage = FakeStorage(malformed)
        val store = store(storage)

        val result = store.snapshot()

        assertTrue(result is PendingShareEventStore.Result.Failure)
        assertEquals(PendingShareEventStore.FailureReason.MALFORMED_DATA, (result as PendingShareEventStore.Result.Failure).reason)
        assertEquals(malformed, storage.value)
    }

    @Test
    fun `concurrent modifications keep every successfully enqueued event`() {
        val store = store(FakeStorage())
        val workers = 16
        val ready = CountDownLatch(workers)
        val start = CountDownLatch(1)
        val done = CountDownLatch(workers)
        val executor = Executors.newFixedThreadPool(workers)

        repeat(workers) { index ->
            executor.execute {
                ready.countDown()
                start.await()
                store.enqueue("event-$index")
                done.countDown()
            }
        }

        assertTrue(ready.await(2, TimeUnit.SECONDS))
        start.countDown()
        assertTrue(done.await(2, TimeUnit.SECONDS))
        executor.shutdownNow()
        assertEquals(workers, store.snapshot().value.size)
    }

    private fun store(storage: FakeStorage, now: Long = 1_000L) =
        PendingShareEventStore(storage) { now }

    private class FakeStorage(
        var value: String? = null,
        private val commitSucceeds: Boolean = true,
    ) : PendingShareEventStore.Storage {
        override fun read(): String? = value

        override fun write(value: String): Boolean {
            if (!commitSucceeds) return false
            this.value = value
            return true
        }
    }
}
