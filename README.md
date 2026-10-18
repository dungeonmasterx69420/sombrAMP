<div align="center">
  <img src="assets/icon/sombra_icon_tile.png" alt="The sombra S mark" width="128">

  <h1>sombrAMP</h1>

  A music player for Jellyfin and Navidrome, by <a href="https://sombra.wtf">sombra</a>. Built on <a href="https://github.com/finamp-app/finamp">Finamp</a>.
</div>

## What it is

sombrAMP is a Sombra product: Finamp's player, redesigned in **System S**, the design system behind
[sombra.wtf](https://sombra.wtf). A 1-bit desktop: ink on black (dark is the default) or on paper white, hard
edges, extruded window shadows and one phosphor colour that marks whatever is live.

It streams and downloads the music on your own Jellyfin or Navidrome server, with everything Finamp does underneath:
gapless playback, offline downloads, transcoding, lyrics, volume normalization, Android Auto and CarPlay, and
playback reporting.

> [!IMPORTANT]
> You **need** access to a [Jellyfin](https://jellyfin.org) server, or a Subsonic server like
> [Navidrome](https://www.navidrome.org). sombrAMP plays your own music from it and doesn't connect to any
> streaming service.

### Navidrome and other Subsonic servers

Servers implementing the [Subsonic API](http://www.subsonic.org/pages/api.jsp) (including the
[OpenSubsonic](https://opensubsonic.netlify.app) extensions), like Navidrome, Gonic or Airsonic, can be used
directly. Just enter the server's address when logging in: sombrAMP detects the kind of server automatically and
also tries Navidrome's default port `4533`.

When the server has no lyrics for a track, sombrAMP looks them up on [LRCLIB](https://lrclib.net), a free lyrics
database, sending it the track's title, artist, album and length. This can be turned off in Settings → Layout &
Theme → Lyrics. Lyrics can also be stored with the music, as `.lrc` files next to the tracks or embedded in them,
which Navidrome picks up on its next scan.

Some features are only available on Jellyfin: Quick Connect, remote control from other clients, editing metadata
and playlist images, and favoriting playlists or genres. Lyrics of downloaded tracks aren't available offline, and
"instant mixes" need the server to be configured with an external agent like Last.fm, otherwise they fall back to
random tracks of the same genre.

## Downloads

The **sombrAMP builds** workflow (`.github/workflows/sombramp.yml`) builds Android, iOS and Windows on every push
and attaches them to the run on the repository's Actions tab:

- **sombrAMP-android**: a release APK. Allow installing from your browser or file manager, then open it. It has
  the same app ID as Finamp, so uninstall Finamp first if you have it.
- **sombrAMP-ios**: an unsigned IPA, for sideloading with a tool that signs it with your own Apple ID, like
  [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io). With
  a free Apple ID the app has to be signed again every 7 days (AltStore and SideStore do that in the background).
  CarPlay and Siri need entitlements a personal Apple ID doesn't get, so they don't work in a sideloaded build.
- **sombrAMP-windows**: the app folder. Unzip it anywhere and run `Finamp.exe`; nothing to install.
- **sombrAMP-windows-msix**: an installer. It is signed with the test certificate in `windows/runner/resources`
  (password `finamp`), so Windows only installs it after that certificate is added to *Local Machine → Trusted
  People*.

Builds of the main branch are also published on the [Releases](https://github.com/dungeonmasterx69420/sombrAMP/releases)
page, which needs no GitHub account: the APK, the IPA, the Windows folder as a zip and the MSIX. Once the Android
app is installed, it offers newer releases itself, on startup and in Settings → Check for updates: it downloads them
and opens Android's installer, which updates the app in place. Releases need the `ANDROID_KEYSTORE_*` repository
secrets, so that every APK is signed with the same key; without them, each build gets a throwaway key and nothing is
released. The secrets the workflow reads are listed at its top.

### Android TV

The same APK runs on Android TV and Google TV, where it's listed on the TV's home screen. To install it, either:

- On the TV, install **Downloader** (by AFTVnews) from the Play Store, open
  `https://github.com/dungeonmasterx69420/sombrAMP/releases/latest` in it, download the `.apk` and allow Downloader to
  install unknown apps when it asks; or
- From a computer, turn on network debugging in the TV's developer options, then
  `adb connect <the TV's address>` and `adb install <the .apk>`.

On a TV, the remote drives everything:

- The D-pad moves the focus, which is ringed in the phosphor, and select opens or plays what has it. Up and down
  also leave text fields.
- Holding select, or the menu key if the remote has one, does what a long press does on a phone: the menu of an album,
  artist or track, the other action of a button.
- On the main screen, back takes the focus to the now playing bar, with play/pause and the player screen behind it;
  back again leaves the app. Media keys on the remote control playback anywhere.
- Sliders, like the seek bar and the settings, move with left and right.
- There's no split screen: select the now playing bar to open the player, and back to return.

## The design

Everything comes from System S; nothing in the look is new to this app.

- **Colour.** Ink, pane and desk greys for everything, plus one phosphor (amber by default; green, cyan and pink
  in Settings → Layout & Theme → Phosphor) for what is live: playback progress, the playing track, downloads and
  focus. The names under album covers are drawn in it too. Album art no longer tints the interface.
- **Type.** Pixelify Sans for titles, buttons and labels; IBM Plex Mono for body text and figures. Both are
  bundled under the SIL Open Font License (`assets/fonts/`).
- **Covers.** Artwork keeps its full colour, framed square on a pane with a 1px ink edge.
- **Shapes.** 1px ink edges, square covers, buttons that invert while pressed and a ring on the default one,
  windows and dialogs with the extruded shadow, toasts and menus with a hard offset shadow.
- **Mark.** The S mark is the in-app logo and every app icon; the sign-in flow is laid out like System S's
  sign-in, with the sombra.wtf wordmark, and the music screen is titled sombra.wtf.

The System S implementation lives in [`lib/sombra/`](lib/sombra): tokens and the Material theme in
`system_s.dart`, and the marks, desk and window widgets in `system_s_widgets.dart`.

### Regenerating the marks and icons

The S mark and the wordmark are copied from System S, which draws them with SVG masks. Flutter and Android can't
render that construction, so they're flattened into plain paths, and every icon and splash image is rendered from
the result:

```sh
pip install shapely svgelements cairosvg pillow
python3 tools/branding/flatten_marks.py     # writes images/sombra_s_mark.svg and images/sombra_wordmark.svg
python3 tools/branding/generate_icons.py    # Android, iOS, macOS, Linux and Windows icons, splash sources
dart run flutter_native_splash:create --path=flutter_native_splash.yaml
```

## Building

sombrAMP is a Flutter app; see [CONTRIBUTING.md](CONTRIBUTING.md) for the toolchain and platform setup it
inherits from Finamp. In short:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## What hasn't changed

To keep upgrades and upstream merges painless, the internals still carry Finamp's names: the Dart package is
`finamp`, the app and bundle IDs are `com.unicornsonlsd.finamp`, and the binary, data and download folder names are
unchanged. Discord Rich Presence still uses Finamp's Discord application and artwork.

## Credits and licence

sombrAMP is built on [Finamp](https://github.com/finamp-app/finamp), the open source Jellyfin music player made by
the Finamp contributors, and on [Jellyfin](https://jellyfin.org). Like Finamp, it is licensed under the
[Mozilla Public License 2.0](LICENSE).
