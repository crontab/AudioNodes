# AudioNodes
#### A framework based on CoreAudio writen in modern Swift (6.0)

_Work in progress_

## Class hierarchy:

- [Node](AudioNodes/Sources/Source.swift)
  - [Source](AudioNodes/Sources/Source.swift): Node
    - [EQFilter](AudioNodes/Sources/EQFilter.swift): Source
    - [EQMultiFilter](AudioNodes/Sources/EQFilter.swift): Source
    - [NoiseGate](AudioNodes/Sources/NoiseGate.swift): Source
    - [VolumeControl](AudioNodes/Sources/Mixer.swift): Source
    - [Mixer](AudioNodes/Sources/Mixer.swift): Source
      - [EnumMixer](AudioNodes/Sources/Mixer.swift): Mixer
    - [Player](AudioNodes/Sources/Player.swift): Source
      - [FilePlayer](AudioNodes/Sources/Player.swift): Player
      - [MemoryPlayer](AudioNodes/Sources/Player.swift): Player
      - [QueuePlayer](AudioNodes/Sources/Player.swift): Player
    - [SineGenerator](AudioNodes/Sources/SineGenerator.swift): Source
    - [System](AudioNodes/Sources/System.swift): Source
      - [Stereo](AudioNodes/Sources/System.swift): System
      - [Voice](AudioNodes/Sources/System.swift): System
  - [Monitor](AudioNodes/Sources/Monitor.swift): Node
    - [Meter](AudioNodes/Sources/Meter.swift): Monitor
      - [Ducker](AudioNodes/Sources/Ducker.swift): Meter
    - [Recorder](AudioNodes/Sources/Recorder.swift): Monitor
      - [FileRecorder](AudioNodes/Sources/Recorder.swift): Recorder
      - [MemoryRecorder](AudioNodes/Sources/Recorder.swift): Recorder

- [AudioData](AudioNodes/Sources/AudioData.swift): StaticDataSource, StaticDataSink
- [AudioFileReader](AudioNodes/Sources/AudioFileReader.swift): StaticDataSource
- [AudioFileWriter](AudioNodes/Sources/AudioFileWriter.swift): StaticDataSink
- [SafeAudioBufferList](AudioNodes/Sources/Utilities.swift)

## Protocols:

- [StaticDataSource](AudioNodes/Sources/AudioData.swift)
- [StaticDataSink](AudioNodes/Sources/AudioData.swift)

## Structs:

- [StreamFormat](AudioNodes/Sources/Source.swift)
- [Waveform](AudioNodes/Sources/Waveform.swift)
