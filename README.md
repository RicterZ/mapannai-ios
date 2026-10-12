# MapAnNai iOS（マップ案内）

English | [中文](README.zh.md) · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [Download IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

Put the places you want to visit on a map, then take your day-by-day travel plan with you.

MapAnNai iOS is the native iPhone and iPad client for MapAnNai Plus. Save restaurants, hotels, and sights, add photos and notes, and arrange visits by trip and day. The client and web app share the places and trips stored on your server, so you can plan on your computer and keep viewing or editing on your phone.

The app opens on My Trips, with its title inside the scrolling page. Pull down the home card list to refresh your trips and places. Ongoing trips appear first as fully visible cards with space between them and a muted green “On the trip” indicator. When none are ongoing, the closest upcoming departure has a full card at the top; the remaining trips stack below, newest first, with year cards separating departure years. When there are no ongoing or upcoming trips, the trip whose departure date is closest to today leads the stack. Each year has a fixed, automatically generated color and pattern; year cards are decorative and cannot be opened. Tap a card to open its full-page itinerary, browse each day, or switch to the map. Day cards summarize visit order, saved times and transport, with a place photo when available. Trip cards use place photos as a subdued background. Close the trip to return to the cards.

## Features

- **Save places and travel notes**: Search saved place titles together with map POIs, tap a map POI, or long-press the map to add a place. Matching saved places appear first, show their place icon and a saved label, and can be reused in itineraries. Keep travel tips, booking details, and memories with each place. Tap a place in the half-height or expanded day itinerary to open its details; closing restores the previous itinerary height. From its details, remove it from the current day while keeping the saved place and other days, or delete it entirely. The place editor shows its address, with location managed by map selection.
- **Plan each day**: Create a trip, keep places in its unscheduled list, and drag them into a day when ready. Add places to its daily itinerary: an empty day starts Route 1, a day with one route appends there, and a day with multiple routes keeps new places unscheduled. Edit a trip using the same name, icon and date-range controls as creation. Move its dates or extend the trip while retaining existing days and plans. Remove individual days from the itinerary, and reuse places you have already saved. When deleting a trip or day, optionally remove its exclusive places while keeping shared places.
- **Arrange visits your way**: Create routes with one or more places within a day and change the visit order to organize different activities. Long-press to select and reorder places in the current day. Swipe right to move, copy to another day, or remove a place from the day. Choose transport between places from an icon panel, then add line or service numbers, departure times, planned durations, and notes. Tap the time at the top right of a place to arrange its visit. Reordering within a route preserves visit times; transport reappears when its original departure and arrival become adjacent in the same direction again.
- **Browse a day on the map**: Tap a day to open its draggable full-height itinerary over the map. Pull down to browse its place cards; the map shows only that day’s places and routes. Switch dates along the compact date strip and swipe place cards with covers, categories and available addresses to highlight each place with a black numbered marker. Connectors show planned distance, or explicitly labeled straight-line distance when unavailable. Transport and time appear only when set, without empty rows. Pull the panel up to the daily itinerary at half or full height, then drag it down to return to the cards. After moving or zooming the map, swiping changes the highlight without resetting your view. The map toolbar provides location and search.
- **See the whole plan on a map**: View saved places and daily routes. Colors distinguish days; tap a saved place to open a white, edge-attached half-height detail panel, pull up for more content or down to return to your itinerary or a route to see its itinerary. In a day view, small, evenly spaced static arrows show the direction between adjacent places, consistently across System Maps, AMap, and Google Maps.
- **View routes and open directions**: Route planning follows each segment’s transport arrangement; the server chooses a mode when none is set. Unsupported routes appear as dashed curves. When you are ready to go, open a place in Apple Maps, AMap, or Google Maps for navigation. Choose your preferred app in Settings → Map and Routes → Navigation Map. Saved official POIs retain their platform identity when available, so System Maps and Google Maps can open the matching place; places without an identity still open by coordinates.
- **Use it on your phone or tablet**: Switch trip dates from the collapsed Liquid Glass itinerary capsule on iOS 26 and later (with a frosted material on earlier systems), pull it up for details, or view the map and itinerary side by side on iPad to compare places and organize your plans.
- **Share travel data with the web app**: Connect to your own MapAnNai Plus server and continue editing the same trip on the web, iPhone, or iPad.

The default background is System Maps (Apple MapKit). Choose System Maps, AMap, or Google Maps in Settings → Map and Routes → Map Background. Google Maps is also available in builds configured with a Google Maps SDK key; otherwise it quietly uses System Maps. This changes the in-app map; search and route planning continue to use your connected server.

## Plan your first trip

1. Connect to your MapAnNai Plus server in the app's settings.
2. Search, tap a map POI, or long-press the map to save places, with notes and photos.
3. Tap the ＋ in My Trips or on the collapsed panel. Search for and select destination cities or provinces first. Give your trip a name, choose an icon from the grid, and select its departure and return dates together on the calendar, then tap Create Trip. Add places to each day and arrange their visit order within routes.
4. Open the day's itinerary while traveling to check places, read your notes, or start navigation. Tap a route title to view it on the map; use its right-hand arrow to show or hide its places.

With route planning enabled, each planned segment's distance appears between its places. Map lines simplify small loops and short backtracks to emphasize visit order; distances retain the original planned values. Opposite-direction overlapping legs are slightly separated near street-level zoom.

Need a server? Follow the [MapAnNai Plus deployment guide](https://github.com/RicterZ/mapannai-plus#deploy-your-own-server), then enter its address and API token, if required, in the client. Searching, saving changes, and route planning require a network connection.

On launch, the map prioritizes your date-based itinerary. When no itinerary provides a location, allowing location access centers the map on your current position. Adding a place shows saved places within 30 km of the map center. Search, results and place previews share the same bottom panel; drag it down to keep just the search field, or tap Back to leave. Selecting a marker previews it; only the Add action changes your itinerary. Travel icons use the illustrated SVG artwork shared with the Web dashboard.

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
