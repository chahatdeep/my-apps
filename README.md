# my-apps

Release builds of my apps, with the version files they check for updates.

| App | Version file | Downloads |
| --- | --- | --- |
| MoreTube (Android phone) | [`moretube/version.json`](moretube/version.json) | [Releases](../../releases) |

Each app reads its `version.json` on launch; when the `versionCode` there is newer than the installed one, it offers to download the APK from the matching GitHub release and hands it to Android's installer.
