package com.example.fieldsync.data

import androidx.room.Database
import androidx.room.RoomDatabase

// Version 1. If you change RecordEntity (for example to add `deleted`), you must
// bump this version and add a migration, or delete the app's data to continue.
@Database(entities = [RecordEntity::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun recordDao(): RecordDao
}
