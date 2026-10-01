# MapAnNai iOS（マップ案内）

English | [中文](README.zh.md) · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [Download IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

Put the places you want to visit on a map, then take your day-by-day travel plan with you.

MapAnNai iOS is the native iPhone and iPad client for MapAnNai Plus. Save restaurants, hotels, and sights, add photos and notes, and arrange visits by trip and day. The client and web app share the places and trips stored on your server, so you can plan on your computer and keep viewing or editing on your phone.

## Features

- **Save places and travel notes**: Search for places or long-press the map to add them. Keep travel tips, booking details, and memories with each place.
- **Plan each day**: Create a trip and add places to its daily itinerary. Add or remove days, shift your travel dates, and reuse places you have already saved. When deleting a trip, optionally remove its exclusive places while keeping shared places.
- **Arrange visits your way**: Create multiple routes within a day and change the visit order to organize different activities.
- **See the whole plan on a map**: View all places, a trip overview, or daily routes. Colors distinguish days; tap a place or route to see its itinerary.
- **View routes and open directions**: Choose walking, driving, or automatic route planning. When you are ready to go, open a place in Apple Maps for navigation.
- **Use it on your phone or tablet**: Switch trip dates from the collapsed itinerary panel on iPhone, pull it up for details, or view the map and itinerary side by side on iPad to compare places and organize your plans.
- **Share travel data with the web app**: Connect to your own MapAnNai Plus server and continue editing the same trip on the web, iPhone, or iPad.

Use the chat icon at the top right of the map to plan with the AI assistant. Configure your model API in Settings first.

## Plan your first trip

1. Connect to your MapAnNai Plus server in the app's settings.
2. Search or long-press the map to save places, with notes and photos.
3. Tap Add Trip in My Trips or the ＋ on the collapsed panel, add places to each day, and arrange their visit order within routes.
4. Open the day's itinerary while traveling to check places, read your notes, or start navigation. Tap a route title to view it on the map; use its right-hand arrow to show or hide its places.

Need a server? Follow the [MapAnNai Plus deployment guide](https://github.com/RicterZ/mapannai-plus#deploy-your-own-server), then enter its address and API token, if required, in the client. Searching, saving changes, and route planning require a network connection.

## Install on iPhone or iPad

Requires **iOS / iPadOS 17 or later**. Releases provide an unsigned `.ipa` that you can sign and install with **AltStore Classic**.

1. Follow the [official AltStore guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore) to install AltServer on your computer and AltStore Classic on your iPhone or iPad. Enable Developer Mode if prompted.
2. Open [Releases](https://github.com/RicterZ/mapannai-ios/releases/latest) on your device, download `MapAnNai-0.0.1-unsigned.ipa`, and save it to Files.
3. Open AltStore Classic → **My Apps** → **＋** in the upper-left corner. Select the IPA and follow the prompts to sign and install it. Keep AltServer reachable as required by AltStore.
4. Apps installed with a free Apple account usually need to be refreshed every **7 days**. Refresh the app in AltStore; see the [AltStore user guide](https://faq.altstore.io/altstore-classic/your-altstore) for connection and automatic refresh instructions.

Use **AltStore Classic**, not AltStore PAL. Re-signing may change the app's Bundle ID, while the AMap key is tied to a Bundle ID. If map authentication fails after installation, rebuild with a key registered for the final Bundle ID; see the [build guide (Chinese)](docs/development.md). Map access has not been verified for arbitrary accounts used to re-sign the app.

## Build from source

See the [build guide (Chinese)](docs/development.md). Pushes to main and manual GitHub Actions runs build an unsigned IPA. Version tags automatically publish a release after the build succeeds.

## License

[MIT](LICENSE). The AMap SDK is subject to its own license terms.
