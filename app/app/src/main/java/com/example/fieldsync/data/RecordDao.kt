package com.example.fieldsync.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface RecordDao {

    @Query("SELECT * FROM records ORDER BY title")
    fun observeAll(): Flow<List<RecordEntity>>

    @Query("SELECT * FROM records WHERE dirty = 1")
    suspend fun dirty(): List<RecordEntity>

    @Query("SELECT * FROM records WHERE id = :id")
    suspend fun byId(id: String): RecordEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: RecordEntity)

    @Query("UPDATE records SET version = :version, dirty = 0 WHERE id = :id")
    suspend fun markSynced(id: String, version: Int)
}
