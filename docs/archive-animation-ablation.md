# Archive entrance animation ablation

Debug-only, opt-in experiments. No flags means the original behavior. Release ignores flags. Keep the same device, trip, scroll position, Reduce Motion setting and cache state across runs. Do not clear real user caches or change the server's data.

## First-stage switches

Pass one launch argument, for example `--archive-ablation=trace,no-motion`.

| Run | Argument value | Only intended difference |
| --- | --- | --- |
| A0 | `trace` | Instrumented baseline |
| A2 | `trace,linear-curve` | Linear detail-content curve, original duration and displacement; card snapshot curve unchanged |
| A3 | `trace,no-motion` | Remove only detail-content's 28pt displacement |
| A5a | `trace,pause-frame-state` | Skip day-frame State commits until card handoff; still collect preferences |
| A5b | `trace,pause-frame-collection` | Omit day-frame measurement views until handoff; restore afterward |
| A6 | `trace,defer-media` | Gate weather tasks until handoff; photo loading already uses the existing handoff gate |

For a device run (relaunching closes the current unsaved UI, so finish editing first):

```sh
xcrun devicectl device process launch --device Hibiki --terminate-existing me.mapannai.ios --archive-ablation=trace,no-motion
# Baseline: relaunch with trace only, or omit all flags to disable tracing as well.
xcrun devicectl device process launch --device Hibiki --terminate-existing me.mapannai.ios --archive-ablation=trace
```

These flags are independent. First test individually, combine only after a measurable win. Weather experiments require real data: demo mode intentionally performs no weather requests. Existing in-memory photo display is not suppressed, so this is not a cold-cache simulation.

## Capture

Use Instruments on Hibiki with Time Profiler, SwiftUI and Animation Hitches. In Points of Interest, filter the `me.mapannai.ios` subsystem, `ArchiveAblation` category. Events: `CardTap` (accepted open action), `DetailVisible` (transition requested), `CardHandoff` (snapshot completion), `Close`, `DayFramesReceived`, `DayFramesCommitted`. They are timestamps, not proof of rendered frames. No trip IDs, coordinates or credentials are logged.

Alternate A0 and each experiment for at least ten openings of the same trip. Measure tap-to-first-frame, main-thread time and longest hitch in the first 150ms, total hitches through handoff, and frame-preference events. Use SwiftUI Instruments for body update counts. Record device/OS/build, cache state, launch flags, run order and results. Capture cold-cache tests separately using isolated test data, not by erasing app storage. Screen recording is visual evidence only and must be consistent across groups.

A3/A5 improvement implicates motion/geometry feedback. A2 improving appearance without reducing hitches implicates timing as an amplifier. A6 improvement implicates weather commits. No performance conclusion has been established merely by adding these switches.

## Rollback

Remove launch arguments and relaunch to return to baseline immediately; no persistent experiment preferences or schema changes exist. Before editing, local copies were saved in ignored `output/archive-ablation-baseline/`. `output/archive-ablation.patch` contains only first-stage experiment source/test changes, excluding pre-existing edits. From the repository root:

```sh
git apply --reverse --check output/archive-ablation.patch
git apply --reverse output/archive-ablation.patch
```

If the check fails after subsequent edits, stop and reconcile the patch; do not overwrite files with the snapshots or reset the worktree. The experiment document can be removed separately if no longer needed.

## Deferred experiments

A1 (derived-data caching), A4 (single content container) and A7 (drop bridge lookup caching) are not implemented in this first stage. Nor does this harness measure media commit timestamps or automatically collect trace statistics. Evaluate the small independent switches first; do not treat unimplemented groups as tested or assume Core Animation eliminates pre-submission main-thread work.
