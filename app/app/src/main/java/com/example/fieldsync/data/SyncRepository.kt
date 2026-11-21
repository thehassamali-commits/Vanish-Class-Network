package com.example.fieldsync.data

import android.content.Context
import kotlinx.coroutines.flow.Flow
import java.util.UUID

class SyncRepository(
    context: Context,
    private val db: AppDatabase,
    private val api: SyncApi
) {
    private val dao = db.recordDao()
    private val prefs = context.getSharedPreferences("sync", Context.MODE_PRIVATE)
    private val deviceId: String = prefs.getString("device_id", null)
        ?: UUID.randomUUID().toString().also { prefs.edit().putString("device_id", it).apply() }

    fun observe(): Flow<List<RecordEntity>> = dao.observeAll()

    /** Creates a new record (id == null) or edits an existing one. Always marks it dirty. */
    suspend fun createOrEdit(id: String?, title: String, note: String) {
        val existing = id?.let { dao.byId(it) }
        dao.upsert(
            RecordEntity(
                id = existing?.id ?: UUID.randomUUID().toString(),
                title = title,
                note = note,
                version = existing?.version ?: 0,
                dirty = true
            )
        )
    }

    /** Sends all dirty records. Students extend this for conflicts and push_id. */
    suspend fun push() {
        val dirty = dao.dirty()
        if (dirty.isEmpty()) return

        val response = api.push(
            PushRequest(
                deviceId = deviceId,
                changes = dirty.map {
                    ChangeDto(
                        id = it.id,
                        baseVersion = it.version,
                        data = mapOf("title" to it.title, "note" to it.note)
                    )
                }
            )
        )

        response.accepted.forEach { dao.markSynced(it.id, it.version) }

        // TODO (student): handle response.conflicts using your conflict policy.
        // Conflicting records currently stay dirty and are retried forever.

        // TODO (student): set push_id on each ChangeDto for idempotent retries.

        // Known gap (graded): an edit made while this push is in flight is marked
        // clean by markSynced() and may be lost. Fix this and explain your fix.
    }

    /** Pulls all pages of changes since the saved cursor. */
    suspend fun pull() {
        var since = prefs.getInt("cursor", 0)
        do {
            val page = api.pull(since)
            for (rec in page.records) {
                val local = dao.byId(rec.id)
                // TODO (student): this check is incomplete. Make sure a dirty local
                // record is never overwritten, and decide what happens to it instead.
                if (local == null || !local.dirty) {
                    dao.upsert(
                        RecordEntity(
                            id = rec.id,
                            title = rec.data["title"].orEmpty(),
                            note = rec.data["note"].orEmpty(),
                            version = rec.version,
                            dirty = false
                        )
                    )
                }
            }
            since = page.cursor
            prefs.edit().putInt("cursor", since).apply()
        } while (page.hasMore)
    }

    suspend fun sync() {
        push()
        pull()
    }
}
