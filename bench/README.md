# Benchmarks

Run `make bench` to append one JSON record to `bench/results.jsonl`. The run
measures startup to first frame under a pseudo-terminal, scan throughput over
1,000 fixture tracks, and median frame time at 200 × 60. It records results;
it does not assert thresholds or run as part of `make check` or CI.

Each line is one run. The file is append-only: keep older records unchanged.
Compare runs from the same host and operating system; timing depends on the
machine. Salam and basalam versions identify the code pins used for each run.

| Field | Meaning |
| --- | --- |
| `schema` | Record format version |
| `date` | UTC time when the record was written |
| `host`, `os`, `arch` | Machine name, operating system and architecture |
| `salam`, `basalam` | Compiler and UI library versions |
| `startup_us` | Median of 12 startup-to-first-frame runs, in microseconds |
| `frame_us_200x60` | Median time per full 200 × 60 repaint, in microseconds |
| `scan_tracks_per_s` | Tracks scanned per second |
| `scan_tracks` | Number of fixture tracks scanned |
| `frames` | Full frames measured for the frame-time median |
| `startup_samples` | Number of startup runs in the median |
