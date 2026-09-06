# CopyPasta

Notes, links and files you save on one device and reach from another, as long
as both are on the same Wi-Fi. Built for personal use.

## How sharing works

The device holding the notes runs a small HTTP server on port **43210**. Two
ways to reach it:

**From a browser (Windows, or anything else).** Open `http://<phone-ip>:43210`,
type the six-digit PIN shown on the phone's Connect screen, and you get the full
list: copy, add, delete, drag files in, download files out. Nothing to install.

**From the app on another device.** Open Connect, pick the device, enter its
PIN once. Notes and their files merge in both directions; the PIN is remembered
after that.

Devices find each other two ways. They announce themselves over UDP broadcast on
port 43211 every three seconds, and if that gets filtered (Android's Wi-Fi stack
and some access points do filter it) **Scan** sweeps the local `/24` for anything
answering `/api/health`. **Add by address** covers the rest.

## Files

Attach anything up to **256 MB** to a note, from the app or by dropping it on the
browser page. Files are stored app-private under their attachment id, so the same
file has the same name on every device.

Sync moves metadata first, then bytes. Each side tells the other which
attachment ids it holds, so only the missing files move, and each transfer is
checked against the SHA-256 recorded when the file was first imported. A file
that arrives with the wrong digest is discarded rather than saved. Deleting a
note deletes its files on every device it reaches.

## Background sharing

On Android, **Keep sharing in the background** on the Connect screen runs a
foreground service so leaving the app, switching apps or locking the screen no
longer stops sharing. The notification carries the address to type into a
browser.

Swiping CopyPasta out of the recents list still stops it: that destroys the
isolate the server runs in, so the service is set to stop with the task rather
than leave a notification standing for a server that is gone.

## Sync rules

Every item carries an id and an `updatedAt`. On merge the newer side wins.
Deletes leave a tombstone for 30 days so they propagate instead of being undone
by the next device that still has the old row.

## Known limits

- **Traffic is plain HTTP.** The PIN keeps other machines on the network out,
  but anything on the wire can be read. Fine for a home network, not for a cafe.
- **Windows will ask about the firewall** the first time the app binds the port.
  A browser talking to the phone needs no permission at all.
- **A VPN on either device usually breaks discovery**, because it moves traffic
  off the local network.

## Fonts

Mukta and JetBrains Mono are bundled in `assets/fonts`, not fetched at run time.
This app is for a network that often has no route to the internet, and a font
that silently falls back to the system face on first launch is the kind of thing
that only shows up on someone else's device.

Both are subset to Latin, punctuation, currency, arrows and maths, which took
them from 1.9 MB to 568 KB. Mukta's Devanagari is dropped; the interface is
English and the platform font covers every script Mukta does not. Both ship
under the SIL Open Font License, registered with Flutter so the texts appear in
`showLicensePage`.

To regenerate after replacing a font, with `pip install fonttools`:

```
pyftsubset Mukta-Regular.ttf --output-file=assets/fonts/Mukta-Regular.ttf \
  --unicodes="U+0000-024F,U+0259,U+1E00-1EFF,U+2000-206F,U+20A0-20BF,\
U+2100-214F,U+2190-21FF,U+2200-22FF,U+FB00-FB06,U+FEFF,U+FFFD" \
  --layout-features='*' --name-IDs='*' --notdef-outline --drop-tables+=DSIG
```

JetBrains Mono is a single variable file. Weight comes from a `FontVariation` on
its `wght` axis in `AppTheme.mono`, not from separate faces, so nothing is ever
a synthesised fake bold.

## Android permissions

Eight, all used: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` and
`CHANGE_WIFI_MULTICAST_STATE` for the LAN server and discovery;
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS` and
`WAKE_LOCK` for background sharing.

`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` and
`READ_EXTERNAL_STORAGE` come in from `open_filex` and are removed from the
merged manifest with `tools:node="remove"`: every file this app opens is in its
own private directory, where `open_filex` skips the permission path entirely.
`RECEIVE_BOOT_COMPLETED` from `flutter_foreground_task` is removed for the same
reason, since nothing here runs on boot.

## Running it

```
flutter pub get
flutter run
flutter test
```

Android builds need AGP 8.11.1, Gradle 8.14 and Kotlin 2.2.20, which are pinned
in `android/settings.gradle.kts` and the Gradle wrapper.
