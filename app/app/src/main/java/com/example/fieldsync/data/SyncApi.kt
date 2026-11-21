package com.example.fieldsync.data

import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

// Change this for a physical phone. See README step 3.
// Emulator: http://10.0.2.2:8000/   Physical phone: http://<laptop-ip>:8000/
const val BASE_URL = "http://10.0.2.2:8000/"

data class ChangeDto(
    val id: String,
    @SerializedName("base_version") val baseVersion: Int,
    val data: Map<String, String>,
    // STUDENT TODO: set a unique push_id per push so the server can ignore retries.
    @SerializedName("push_id") val pushId: String? = null
)

data class PushRequest(
    @SerializedName("device_id") val deviceId: String,
    val changes: List<ChangeDto>
)

data class AcceptedDto(val id: String, val version: Int)

data class PushResponse(
    val accepted: List<AcceptedDto>,
    val conflicts: List<Map<String, Any?>>
)

data class RecordDto(
    val id: String,
    val data: Map<String, String>,
    val version: Int,
    val seq: Int
)

data class PullResponse(
    val records: List<RecordDto>,
    val cursor: Int,
    @SerializedName("has_more") val hasMore: Boolean
)

interface SyncApi {
    @POST("sync/push")
    suspend fun push(@Body body: PushRequest): PushResponse

    @GET("sync/pull")
    suspend fun pull(@Query("since") since: Int): PullResponse
}
