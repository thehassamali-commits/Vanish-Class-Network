package com.example.fieldsync.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "records")
data class RecordEntity(
    @PrimaryKey val id: String,
    val title: String,
    val note: String,
    // Last server version this device has seen or had accepted.
    // 0 means the record was created offline and never accepted.
    val version: Int,
    // True when local changes have not been accepted by the server yet.
    val dirty: Boolean
    // STUDENT TODO: add a `deleted` field for tombstones.
)
