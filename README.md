# MapAnNai iOS（マップ案内）

English | [中文](README.zh.md) · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [Download IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

Put the places you want to visit on a map, then take your day-by-day travel plan with you.

MapAnNai iOS is the native iPhone and iPad client for MapAnNai Plus. Save restaurants, hotels, and sights, add photos and notes, and arrange visits by trip and day. The client and web app share the places and trips stored on your server, so you can plan on your computer and keep viewing or editing on your phone.

## Features

- **Save places and travel notes**: Search for places, tap a map POI, or long-press the map to add a place. Keep travel tips, booking details, and memories with each place.
- **Plan each day**: Create a trip, keep places in its unscheduled list, and drag them into a day when ready. Add places to its daily itinerary. Add or remove days, shift your travel dates, and reuse places you have already saved. When deleting a trip or day, optionally remove its exclusive places while keeping shared places.
- **Arrange visits your way**: Create multiple routes within a day and change the visit order to organize different activities. Add transport between places, including line or service numbers, departure times, planned durations, and notes. Tap the time at the top right of a place to arrange its visit. Reordering within a route preserves visit times; transport reappears when its original departure and arrival become adjacent in the same direction again.
- **See the whole plan on a map**: View all places, a trip overview, or daily routes. Colors distinguish days; tap a place or route to see its itinerary. In a day view, small, evenly spaced static arrows show the direction between adjacent places, consistently across System Maps, AMap, and Google Maps.
- **View routes and open directions**: Choose walking, driving, or automatic route planning. When you are ready to go, open a place in Apple Maps, AMap, or Google Maps for navigation. Choose your preferred app in Settings → Open Map. Saved official POIs retain their platform identity when available, so System Maps and Google Maps can open the matching place; places without an identity still open by coordinates.
- **Use it on your phone or tablet**: Switch trip dates from the collapsed Liquid Glass itinerary capsule on iOS 26 and later (with a frosted material on earlier systems), pull it up for details, or view the map and itinerary side by side on iPad to compare places and organize your plans.
- **Share travel data with the web app**: Connect to your own MapAnNai Plus server and continue editing the same trip on the web, iPhone, or iPad.

Use the chat icon at the top right of the map to plan with the AI assistant. Configure your model API in Settings first. Settings also lets you hide the chat icon (off by default). Replies can continue briefly in the background; interrupted replies retain the text already received and are never automatically resent. Assistant replies support Markdown tables; swipe wide tables horizontally to read all columns.

The default background is System Maps (Apple MapKit). Choose System Maps, AMap, or Google Maps in Settings → Map Background. Google Maps is also available in builds configured with a Google Maps SDK key; otherwise it quietly uses System Maps. This changes the in-app map; search and route planning continue to use your connected server.

## Plan your first trip

1. Connect to your MapAnNai Plus server in the app's settings.
2. Search, tap a map POI, or long-press the map to save places, with notes and photos.
3. Tap Add Trip in My Trips or the ＋ on the collapsed panel, add places to each day, and arrange their visit order within routes.
4. Open the day's itinerary while traveling to check places, read your notes, or start navigation. Tap a route title to view it on the map; use its right-hand arrow to show or hide its places.

With route planning enabled, each planned segment's distance appears between its places.

Need a server? Follow the [MapAnNai Plus deployment guide](https://github.com/RicterZ/mapannai-plus#deploy-your-own-server), then enter its address and API token, if required, in the client. Searching, saving changes, and route planning require a network connection.


On launch, allow location access to center the map on your nearest saved place. If location is unavailable, the app keeps its date-based starting view.

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
