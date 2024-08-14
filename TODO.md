
- Check if system input and output callbacks are on the same thread.
- Rename `.input` to `.source`. System input should push data via the monitor connector but also provide buffered source connection.
- To avoid double didEndPlaying, use `forcedDisable()` that doesn't produce a ramp. Should be called from players at end of playback.
- Restructure players and recorders: there's probably no need for protocols
