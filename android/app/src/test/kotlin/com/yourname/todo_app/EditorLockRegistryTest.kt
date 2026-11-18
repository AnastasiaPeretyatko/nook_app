package com.yourname.todo_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorLockRegistryTest {
    @Test
    fun `acquires an unlocked note`() {
        val registry = EditorLockRegistry()

        assertTrue(registry.tryAcquire(noteId = 1, ownerId = "editor-a"))
        assertTrue(registry.isLocked(1))
        assertEquals(setOf(1), registry.getLockedIds())
    }

    @Test
    fun `rejects a competing owner`() {
        val registry = EditorLockRegistry()

        assertTrue(registry.tryAcquire(1, "editor-a"))
        assertFalse(registry.tryAcquire(1, "share-b"))
    }

    @Test
    fun `same owner acquisition is idempotent without reference counting`() {
        val registry = EditorLockRegistry()

        assertTrue(registry.tryAcquire(1, "editor-a"))
        assertTrue(registry.tryAcquire(1, "editor-a"))
        assertTrue(registry.release(1, "editor-a"))
        assertFalse(registry.isLocked(1))
    }

    @Test
    fun `only the owning editor can release a lock`() {
        val registry = EditorLockRegistry()
        registry.tryAcquire(1, "editor-a")

        assertFalse(registry.release(1, "share-b"))
        assertTrue(registry.isLocked(1))
        assertTrue(registry.release(1, "editor-a"))
    }

    @Test
    fun `different notes can be locked independently`() {
        val registry = EditorLockRegistry()

        assertTrue(registry.tryAcquire(1, "editor-a"))
        assertTrue(registry.tryAcquire(2, "share-b"))
        assertEquals(setOf(1, 2), registry.getLockedIds())
    }

    @Test
    fun `owner cleanup only releases that owners locks`() {
        val registry = EditorLockRegistry()
        registry.tryAcquire(1, "editor-a")
        registry.tryAcquire(2, "editor-a")
        registry.tryAcquire(3, "share-b")

        assertEquals(2, registry.releaseAll("editor-a"))
        assertFalse(registry.isLocked(1))
        assertFalse(registry.isLocked(2))
        assertTrue(registry.isLocked(3))
    }

    @Test
    fun `concurrent acquisition grants exactly one owner`() {
        val registry = EditorLockRegistry()
        val workers = 16
        val ready = CountDownLatch(workers)
        val start = CountDownLatch(1)
        val done = CountDownLatch(workers)
        val executor = Executors.newFixedThreadPool(workers)
        val acquired = mutableListOf<Boolean>()

        repeat(workers) { index ->
            executor.execute {
                ready.countDown()
                start.await()
                synchronized(acquired) {
                    acquired += registry.tryAcquire(1, "owner-$index")
                }
                done.countDown()
            }
        }

        assertTrue(ready.await(2, TimeUnit.SECONDS))
        start.countDown()
        assertTrue(done.await(2, TimeUnit.SECONDS))
        executor.shutdownNow()

        assertEquals(1, acquired.count { it })
        assertEquals(setOf(1), registry.getLockedIds())
    }
}
