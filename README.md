# Field Sync: Offline-First Data Collector

## What you are building
An Android app that lets a field worker create and edit records with no network,
store them locally, and sync them to a server later. The server is provided
(`server/`). You build the app's sync logic and the parts marked TODO.

## Folder layout
```
field-sync/
├── README.md
├── .gitignore
├── server/                 # provided Python server (run this first)
│   ├── main.py
│   ├── test_server.py
│   └── requirements.txt
└── app/                    # Android Studio project (Kotlin + Jetpack Compose)
    ├── settings.gradle.kts
    ├── build.gradle.kts
    ├── gradle.properties
    └── app/
        ├── build.gradle.kts
        └── src/main/
            ├── AndroidManifest.xml
            └── java/com/example/fieldsync/
                ├── MainActivity.kt
                └── data/
                    ├── AppDatabase.kt
                    ├── RecordDao.kt
                    ├── RecordEntity.kt
                    ├── SyncApi.kt
                    └── SyncRepository.kt
```

## Setup

### 1. Run the server
Open a terminal in the `server/` folder. The database file `server.db` is created in
the folder you run the command from, so always start the server from `server/`.

macOS / Linux:
```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Windows (PowerShell):
```powershell
cd server
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

In a second terminal (same folder, venv active):
```bash
python test_server.py http://localhost:8000
```
You must see `ALL PASSED`. If not, fix the server before touching the app.
To reset all data, stop the server and delete `server/server.db`.

### 2. Open the app
1. Open the `app/` folder in Android Studio (Ladybug 2024.2.1 or newer).
2. Let Gradle sync. Android Studio will create the Gradle wrapper automatically.
3. If it asks to upgrade the Android Gradle Plugin or Kotlin, decline the upgrade
   and ask your instructor. The versions in this project are pinned on purpose.

### 3. Point the app at the server
- **Android emulator:** `BASE_URL` is already `http://10.0.2.2:8000/`. This address
  reaches your laptop's `localhost`.
- **Physical phone:** put the laptop and phone on the same Wi-Fi. Find the laptop's
  LAN IP (`ipconfig` on Windows, `ifconfig` or `ip a` on Linux/macOS, usually
  `192.168.x.x`). Change `BASE_URL` in `data/SyncApi.kt` to `http://<laptop-ip>:8000/`
  (keep the trailing slash). Your firewall must allow inbound port 8000.

### 4. Run the app
Press Run. The app shows two fields, Title and Note, a **Save locally** button, and a
**Sync** button. Records you save appear in the list marked "(unsynced)" until a sync
succeeds.

## What is provided (working)
- Local records: create and edit, stored in Room (SQLite).
- Push: sends records marked dirty to `/sync/push`. Accepted records are marked clean.
- Pull: fetches changes from `/sync/pull` using a stored cursor, page by page.
- Sync button that runs push, then pull.

## What you must build (TODO comments in the code)
Each item is graded. Do the design work (item 1) before writing code.

1. **Design document (before coding), 1-2 pages.** Answer in writing:
   - How does the server know a write is stale? (Read `server/main.py`.)
   - Your conflict policy: what happens when `base_version` does not match, and why.
     Options include last-write-wins by timestamp, field-level merge, keeping both
     copies, or asking the user. You must justify the choice.
   - How your app avoids losing a local edit that is made while a push is in flight.
2. **Conflict handling.** Implement your policy in `SyncRepository.push()` where the
   `conflicts` list is handled. Also change `pull()` so it never overwrites a dirty
   local record.
3. **Idempotent retries.** A phone may resend a push after a timeout. Send a unique
   `push_id` from the app for each push, and make the server in `main.py` ignore a
   push_id it has already processed (no duplicate writes, no double version bumps).
4. **Deletes.** Implement delete with a tombstone (a `deleted` flag that syncs like
   any other change), so deletions reach other devices.
5. **Known gap.** `SyncRepository.push()` marks accepted records clean. If the user
   edits a record while the push is in flight, that edit can be marked clean and lost.
   Fix it and explain the fix.
6. **Test plan, at least five scenarios.** Include: airplane mode mid-sync, two
   devices editing the same record offline, a duplicate push, the server being down,
   and the app being killed during a sync. Record expected and actual results.

## Deliverables
- Design document (1-2 pages), including your conflict policy and reasons.
- Working app and server, with a two-device demo. The instructor will inject a failure.
- Test log with at least five scenarios.
- Individual viva (10 minutes): you explain your code and one trade-off.
- A short note listing which parts were generated by AI and which you wrote or changed.

## Rules
- AI tools are allowed. Disclose their use in the note above.
- You must be able to explain every line you submit. Expect questions on your code,
  not on the starter code.

## Troubleshooting
| Symptom | Likely cause and fix |
|---|---|
| `test_server.py` fails to connect | Server not running, or not started from `server/`. |
| Sync failed: `Failed to connect` on a phone | Wrong `BASE_URL`, phone not on the same Wi-Fi, or firewall blocks port 8000. |
| Sync failed on the emulator | Server not running on the laptop. `10.0.2.2` is the host machine. |
| Gradle errors about AndroidX | Check that `gradle.properties` contains `android.useAndroidX=true`. |
| Cleartext HTTP blocked | Check that `AndroidManifest.xml` has `android:usesCleartextTraffic="true"`. Development only. |
| Records vanish after reinstall | Expected: local data is deleted with the app. |
| Server returns 422 | The request body does not match the server's model. Compare with `SyncApi.kt`. |
