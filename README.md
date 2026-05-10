# puggy-bank

## Development (Windows)

### `flutter test` fails with “Could not acquire the lock … hooks_runner … .lock”

That comes from Flutter’s **native assets / hooks** step (often `sqlite3`, `jni`, `objective_c`) when another `dart`/`flutter` process still holds the lock, or **OneDrive** delays file access under `.dart_tool`.

1. Close other terminals running `flutter` / `dart` (including Cursor’s background tasks).
2. From the repo root, run:

   ```powershell
   .\scripts\flutter_test_windows.ps1
   ```

   It deletes stale `**/.lock` files under `.dart_tool/hooks_runner`, runs `flutter pub get`, then `flutter test`.

   If locks are still **in use**, stop other Flutter/Dart jobs, then:

   ```powershell
   .\scripts\flutter_test_windows.ps1 -StopDartProcesses
   ```

   (`-StopDartProcesses` kills **all** `dart`/`flutter` processes on the machine—only use when nothing else needs them.)

3. **Do not** run `flutter config --no-enable-native-assets` for this app. Dependencies such as **`sqlite3`** and **`objective_c`** need **Dart code/data assets** during `flutter test`. If you previously disabled them, turn them back on (machine-wide Flutter SDK setting):

   ```powershell
   flutter config --enable-native-assets
   flutter config --enable-dart-data-assets
   ```

   Then run `.\scripts\flutter_test_windows.ps1 -StopDartProcesses` again.

4. Long-term: keep the repo **outside OneDrive** (e.g. `C:\dev\puggy-bank`) to reduce hook **lock** friction while keeping native assets **enabled**.