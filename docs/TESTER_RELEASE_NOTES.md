# Uzume beta — notes for testers

Thank you for trying Uzume. This page is what we know is rough, so you don't spend your time reporting it. Anything not on it, please tell us.

## What's new in 0.9.1

**If you downloaded 0.9.0, please replace it with this version.** 0.9.0 could run your Mac out of memory while preparing long local songs.

- **Long local songs no longer run your Mac out of memory.** Preparing a long song could take tens of gigabytes and hang Uzume and the Mac. It now stays at about 2–3 GB, however long the songs.
- **Local playlists get ready about three times faster.** Start now appears within seconds of opening a folder, and a long playlist is fully prepared in a few minutes.
- **Safer at fast tempos.** Two scenes, Membrane and Waveform, flashed faster than accessibility guidelines allow in part of the screen. Both are fixed, and every scene now passes a stricter check.
- **The right song, reliably.** With Spotify or Apple Music, Uzume checks a song's title, artist and length before analysing it, and skips a song it can't match instead of guessing.
- **Streaming scenes ease into each song** instead of lurching for the first few seconds.
- **High sample rates.** Scenes that follow individual instruments now work when your Mac plays at 88.2 kHz or above.

## What you need

- **A Mac with Apple silicon** (M1 or later) running **macOS 15 Sequoia or later**. Intel Macs can't open the app.
- **macOS 15 itself is untested.** We built and tested on macOS 26. If Uzume won't open, or shows no visuals, on macOS 15, that's exactly the report we need.

## How it listens

- **Spotify or Apple Music:** Uzume listens to what your Mac plays (it asks to record system audio; your audio never leaves your Mac — Uzume only looks up song details, such as genre and length, on Apple's iTunes and MusicBrainz). Start the music in your player when Uzume says it's ready.
- **Local files** (File › Open Local File, or drop files on the window): Uzume plays them itself, and the visuals are timed to the music exactly.
- **Streaming is slightly behind.** With Spotify or Apple Music, the parts of a scene that follow individual instruments run about 2.5 seconds behind the music. The overall energy and the beat follow immediately. Local files don't have this delay.
- **Bluetooth headphones and speakers** add their own delay. Uzume now holds its beat-timed accents back to match, but this hasn't been checked with real AirPods yet: if the visuals look early or late on Bluetooth, tell us. Wired or built-in speakers are best for judging timing.

## Known limits

- **Scanning a Spotify playlist from the screen** reads the English Spotify desktop app. It may miscount on other languages, compact view, or very small windows, and hasn't been tried on playlists over 100 songs. The web player isn't supported.
- **Scene changes are hard cuts** for now.
- **Fireflies and Kagura respond to a song's quiet and loud parts only with local files.** When streaming, they follow the song's overall energy: the fireflies don't thin out in quiet stretches.
- **Scene preferences aren't in this build.** The Settings for hiding scene families and choosing quality, and the keys for "more / less like this", aren't in the beta yet.
- **On M1-family Macs** one scene (Fractal Tree) isn't shown. **M1- and M2-family Macs** draw the visuals at a slightly lower resolution on large displays and let macOS scale them up, so they stay smooth.

## If something goes wrong

- **Help › Report a Problem…** saves a zip of Uzume's recent log messages, any crash or freeze reports, and your Mac's model, macOS version and graphics chip. It includes no audio, and Uzume sends nothing: the zip opens in Finder, and a GitHub issue page opens for you to attach it and say what happened.
- If Uzume **crashes or you force-quit it**, it offers the same report the next time it opens.
- **If the visuals freeze,** please wait about five seconds before force-quitting. Uzume notices the freeze and records where it's stuck, which is what makes it fixable.
