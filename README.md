# my-apps

Release builds of my apps, with the version files they check for updates.

| App | Package | Version file | Downloads |
| --- | --- | --- | --- |
| MoreTube (Android phone) | `com.praiselab.tube` | [`moretube/version.json`](moretube/version.json) | [Releases](../../releases?q=moretube-v) |
| MoreTube TV (Android / Google TV) | `com.praiselab.tubetv` | [`moretube-tv/version.json`](moretube-tv/version.json) | [Releases](../../releases?q=moretube-tv) |

**Install page:** https://chahatdeep.github.io/my-apps

Each app reads its `version.json` on launch (and from its settings); when the `versionCode` there is newer than the installed one, it offers to download the APK from the matching GitHub release and hands it to Android's installer.

## Installing for the first time

Download the latest APK from Releases and open it on the device. Android will ask once to allow installs from that source; after that, updates come from inside the app.
