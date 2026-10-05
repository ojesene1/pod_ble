# Mobile (Flutter)

```
mobile/
└── pod_ble_client/          Flutter package: everything the app needs to talk to a pod
    ├── lib/src/protocol.dart        byte layouts (pure Dart, mirrors firmware/pod-protocol)
    ├── lib/src/pod_connection.dart  scan / connect / subscribe, on flutter_blue_plus
    ├── test/                        golden-vector tests shared with the firmware
    └── example/                     bench-test app: scan, connect, watch steps arrive
```

The patient/clinician app (Platforms) doesn't live here. It depends on this package:

```yaml
# in the app's pubspec.yaml
dependencies:
  pod_ble_client:
    git:
      url: <this repo's URL>
      path: mobile/pod_ble_client
      ref: main
```

## Using it

```dart
import 'package:pod_ble_client/pod_ble_client.dart';

await PodScanner.start();                       // filters by the Step Record Service UUID
final result = (await PodScanner.results.firstWhere((r) => r.isNotEmpty)).first;
await PodScanner.stop();

final pod = await PodConnection.connect(result.device);   // sets the pod clock, checks versions
pod.records().listen((step) async {
  await store(pod.podId, step);                 // persist first...
  await pod.ack(step.seq);                      // ...then ack (no-op on the pod until flash storage lands)
});
```

Delivery is at-least-once: dedup on `(podId, seq)`.

## Running the tests

```bash
cd mobile/pod_ble_client
flutter pub get
flutter test
```

## Running the bench app on a phone

The example ships only `lib/` and `pubspec.yaml`. Generate the platform folders once, then add the Bluetooth permissions:

```bash
cd mobile/pod_ble_client/example
flutter create . --platforms=android,ios --project-name pod_ble_example
rm test/widget_test.dart   # template test for the counter app; doesn't apply here
```

`flutter create` keeps the existing `lib/main.dart` and `pubspec.yaml`. The generated `android/` and `ios/` folders are fine to commit.

**Android:** in `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` and above `<application>`:

```xml
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

**iOS:** in `ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connects to your pod to collect step data.</string>
```

Then `flutter run` with a phone attached (BLE doesn't work in emulators/simulators). With the pod firmware's default `simulate-steps` feature, a fake step shows up every second.

The same permission entries go into the real app.

## Licence note: flutter_blue_plus

flutter_blue_plus 2.x uses the FlutterBluePlus License: free for personal, nonprofit and **educational** use; commercial use needs a paid licence. The capstone is covered, and `podBleLicense` in `pod_connection.dart` is set to `License.nonprofit`. If the pod is ever commercialised, either buy a licence or swap the BLE layer. Only `pod_connection.dart` depends on it.
