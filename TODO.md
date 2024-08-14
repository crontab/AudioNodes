
- To avoid double didEndPlaying, use `forcedDisable()` that doesn't produce a ramp. Should be called from players at end of playback.
- Restructure players and recorders: there's probably no need for protocols
