package com.example.fieldsync

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.room.Room
import com.example.fieldsync.data.AppDatabase
import com.example.fieldsync.data.BASE_URL
import com.example.fieldsync.data.SyncApi
import com.example.fieldsync.data.SyncRepository
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

class MainActivity : ComponentActivity() {

    private val repo by lazy {
        val db = Room.databaseBuilder(this, AppDatabase::class.java, "fieldsync.db").build()
        val api = Retrofit.Builder()
            .baseUrl(BASE_URL)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(SyncApi::class.java)
        SyncRepository(this, db, api)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                FieldScreen(repo)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FieldScreen(repo: SyncRepository) {
    val records by repo.observe().collectAsState(initial = emptyList())
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(
            value = title,
            onValueChange = { title = it },
            label = { Text("Title") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = note,
            onValueChange = { note = it },
            label = { Text("Note") },
            modifier = Modifier.fillMaxWidth()
        )
        Row(Modifier.padding(vertical = 8.dp)) {
            Button(onClick = {
                scope.launch {
                    repo.createOrEdit(null, title, note)
                    title = ""
                    note = ""
                }
            }) { Text("Save locally") }

            Spacer(Modifier.width(8.dp))

            Button(onClick = {
                scope.launch {
                    status = try {
                        repo.sync()
                        "Sync OK"
                    } catch (e: Exception) {
                        "Sync failed: ${e.message}"
                    }
                }
            }) { Text("Sync") }
        }
        Text(status)
        HorizontalDivider()
        LazyColumn {
            items(records, key = { it.id }) { r ->
                ListItem(
                    headlineContent = { Text(r.title) },
                    supportingContent = {
                        Text(r.note + if (r.dirty) "  (unsynced)" else "")
                    }
                )
            }
        }
    }
}
