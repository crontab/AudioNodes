# AudioNodes
#### A framework based on CoreAudio writen in Swift 6

_Work in progress, no documentation is available at the moment_

## Class hierarchy:

- [Node](AudioNodes/Sources/Source.swift)
  - [Source](AudioNodes/Sources/Source.swift)
    - [EQFilter](AudioNodes/Sources/EQFilter.swift)
    - [EQMultiFilter](AudioNodes/Sources/EQFilter.swift)
    - [NoiseGate](AudioNodes/Sources/NoiseGate.swift)
    - [VolumeControl](AudioNodes/Sources/Mixer.swift)
    - [Mixer](AudioNodes/Sources/Mixer.swift)
      - [EnumMixer](AudioNodes/Sources/Mixer.swift)
    - [Player](AudioNodes/Sources/Player.swift)
      - [FilePlayer](AudioNodes/Sources/Player.swift)
      - [MemoryPlayer](AudioNodes/Sources/Player.swift)
      - [QueuePlayer](AudioNodes/Sources/Player.swift)
    - [SineGenerator](AudioNodes/Sources/SineGenerator.swift)
    - [System](AudioNodes/Sources/System.swift)
      - [Stereo](AudioNodes/Sources/System.swift)
      - [Stereo.Input](AudioNodes/Sources/System.swift)
  - [Monitor](AudioNodes/Sources/Monitor.swift)
    - [Meter](AudioNodes/Sources/Meter.swift)
      - [Ducker](AudioNodes/Sources/Ducker.swift)
    - [Recorder](AudioNodes/Sources/Recorder.swift)
      - [FileRecorder](AudioNodes/Sources/Recorder.swift)
      - [MemoryRecorder](AudioNodes/Sources/Recorder.swift)

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
