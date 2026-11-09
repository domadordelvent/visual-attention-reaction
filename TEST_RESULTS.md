# Final verification

Verified on **10 November 2026** using **Godot 4.7.2.stable.official.ed1daf0bf** on Ubuntu Linux, with OpenGL Compatibility rendering and PulseAudio.

| Suite | Result |
| --- | --- |
| Core generation, both mode flows, reaction times, statistics and history | **186,513 checks; 0 failures** |
| Real rendering, GUI input, both mode/history selectors, figures and resizing | **272 checks; 0 failures** |
| Real PulseAudio mixing, interface sounds, mute/unmute and silence during trials | **215 checks; 0 failures** |
| Total | **187,000 checks; 0 failures** |

## Coverage

- Normal mode: one target definition per block; Advanced mode: two distinct definitions, both presented in each block.
- Four blocks of ten stimuli, twelve target appearances, target changes, safe near-target distractors and randomized intervals.
- Precise first-response timing, duplicate prevention, late-response boundaries, hits, omissions, false alarms, correct rejections and premature responses.
- Mean, median, fastest and slowest valid reaction times; empty/zero-hit cases and accuracy.
- Completed-session persistence, ten-entry retention, Normal/Advanced filtering, non-destructive loading, malformed files, failed saves, interruption and restart behavior.
- Actual mouse input and rendered figures at 360×480, 800×900 and 1280×720; separated Advanced previews and equal-diagonal diamonds.
- Generated mono PCM streams, UI-to-Master routing, unclipped mixer output, start/completion cues and mute controls. Stimuli, responses, countdowns and target announcements remain silent. Audio leaves the tested 250.123 ms reaction time unchanged.

The existing rendered suite initially used 50 ms timer waits that could resume before the draw callback, producing cascading test failures. These were replaced with completed-frame synchronization, and an assertion count was added. The final suite passes for both modes. **No production gameplay scripts, mechanics, timing or scoring were changed for this release.**

## Screenshot

`screenshots/gameplay.png` is an unedited 800×900 screenshot captured directly from the application's real Godot viewport during the successful rendered Normal-mode test. It shows a visible stimulus, block/session progress, and the Mute and End test controls. The tests advance deadlines to exercise all states efficiently; the screenshot does not represent a human reaction-time result.

A separate real-time capture attempt was interrupted by the desktop taking focus, correctly ending that incomplete session. The published capture comes from the passing rendered suite. No personal history or desktop content appears in it.

## Data and repository preparation

Automated sessions save temporary history files under `/tmp`, and remove them after verification. No saved sessions, test-result JSON, credentials, Godot caches, local export builds or MP4 recording are included in the repository. Source tests remain available to reproduce verification. The MIT license and Godot 4 ignore rules are included.

Other Godot projects were fingerprinted before release preparation and verified unchanged afterwards, including Abstract Visual Attention & Reaction.

## Limitations

Testing covers this Ubuntu desktop environment. Other operating systems, exported binaries and the optional web export were not tested. Audio was verified at the real system mixer, not by a human listening assessment. Software reaction times are not calibrated for physical display or input-device latency. The application is for cognitive practice, not a standardized clinical assessment.
