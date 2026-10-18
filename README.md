# MapAnNai iOS（マップ案内）

English | [中文](README.zh.md) · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [Download IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

<img width="2249" height="1447" alt="screenshots" src="https://github.com/user-attachments/assets/9be410d8-546f-4e5d-b21d-4b025ca75937" />


Put the places you want to visit on a map, then carry your day-by-day travel plan in your pocket.

MapAnNai iOS is the native iPhone and iPad app for [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus). It works with your own server, so a trip planned on the web is ready on your phone, and changes made on the road show up everywhere.

## What you can do

- **Collect places.** Search, tap a point of interest, or long-press the map to save restaurants, hotels and sights. Add a cover photo and notes such as booking details or travel tips.
- **Plan trips day by day.** Create a trip with its destinations and dates, then add places to each day. Group them into routes, reorder visits, and note visit times, transport, train numbers and departures. Mark individual visits or transport legs as highlights in their schedule editor; these settings sync with the web.
- **See your plan on the map.** Each day has its own color. Routes connect places in visit order, with planned distances between stops. Tap a place or route to open it.
- **Look back at your trips.** My Trips shows upcoming and ongoing trips first. Past trips are stacked as cards and grouped by year. Each day reads like a chapter, with photos, the route and the day's weather.
- **Plan with AI.** Describe your next trip in chat. The assistant can ask follow-up questions, suggest dates and draft an itinerary for you to review. AI runs on your server and uses a model you configure.
- **View a whole-trip guide.** Open a read-only route overview from trip details and pinch to zoom without selecting places or changing the live map.
- **Share a trip.** Export the whole trip as a long image with routes and photos, ready to send or save to Photos.
- **Navigate when it's time to go.** Open any place in Apple Maps, AMap or Google Maps.

Works on iPhone and iPad. On iPad, the map and itinerary sit side by side. In landscape, swipe horizontally through the trip information and daily chapters, with their content cards aligned at the top. The map can use Apple Maps, AMap or Google Maps.

## Getting started

1. Set up a MapAnNai Plus server by following the [deployment guide](https://github.com/RicterZ/mapannai-plus#deploy-your-own-server).
2. Open Settings in the app, then enter the server address and, if required, its API token.
3. Tap ＋ on My Trips to create a trip. Choose destinations, a name, an icon and dates.
4. Search for or long-press places to save them, then add them to each day.
5. On the road, open today's itinerary to check places, read your notes, or start navigation.

Searching, saving and route planning require a network connection.

## Install

Requires **iOS / iPadOS 17 or later**. Each release includes an unsigned `.ipa` that you can sign and install with **AltStore Classic**.

1. Install AltServer on your computer and AltStore Classic on your device by following the [AltStore guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore). Enable Developer Mode if prompted.
2. On your device, download the latest IPA from [Releases](https://github.com/RicterZ/mapannai-ios/releases/latest) and save it to Files.
3. In AltStore Classic, open **My Apps**, tap **＋**, choose the IPA, then follow the prompts.
4. Apps installed with a free Apple account usually need to be refreshed every **7 days** in AltStore.

Use AltStore Classic, not AltStore PAL. Re-signing may change the Bundle ID, and the AMap key is tied to one. If the AMap background fails to load, switch to Apple Maps in Settings.

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The map SDK keys are embedded at build time; app users never enter them.

| Key | Required | Purpose |
| --- | --- | --- |
| `AMAP_IOS_KEY` | For the AMap background | AMap iOS SDK key, bound to the app's Bundle ID (`me.mapannai.ios` by default) |
| `GOOGLE_MAPS_IOS_KEY` | Optional | Google Maps iOS SDK key; without it the app uses Apple Maps instead |

Apple Maps needs no key. Server addresses, API tokens and AI keys are entered in the app's Settings, not at build time.

```sh
python3 Scripts/fetch-sdk.py                         # download the official AMap SDK
cp Config/Local.xcconfig.example Config/Local.xcconfig  # fill in the keys above
xcodegen generate
open MapAnNai.xcodeproj
```

`Config/Local.xcconfig` is ignored by Git. For GitHub Actions builds, set the same names as repository secrets.

## License

[MIT](LICENSE). Map SDKs are subject to their own license terms.
