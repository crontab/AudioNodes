//
//  AudioFileWriter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 14.08.24.
//

import Foundation
import CoreAudio
import AudioToolbox


public final class AudioFileWriter: StaticDataSink {

	public final let url: URL
	public final let format: StreamFormat
	public final let fileRef: ExtAudioFileRef


	public init(url: URL, format: StreamFormat, fileSampleRate: Double, compressed: Bool, async: Bool) throws {
		self.url = url
		self.format = format

		var fileRef: ExtAudioFileRef?

		let channels: UInt32 = format.isStereo ? 2 : 1
		var fileDescr =
			compressed ?
				AudioStreamBasicDescription(mSampleRate: fileSampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger, mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: channels, mBitsPerChannel: 0, mReserved: 0) :
				AudioStreamBasicDescription(mSampleRate: fileSampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger, mBytesPerPacket: 2 * channels, mFramesPerPacket: 1, mBytesPerFrame: 2 * channels, mChannelsPerFrame: channels, mBitsPerChannel: 16, mReserved: 0)

		let status = ExtAudioFileCreateWithURL(url as CFURL, compressed ? kAudioFileM4AType : kAudioFileAIFFType, &fileDescr, nil, AudioFileFlags.eraseFile.rawValue, &fileRef)
		guard status == noErr, let fileRef else {
			DLOG("AudioFileWriter: open failed (\(status))")
			throw AudioError.fileWrite(code: status)
		}

		var clientDescr = AudioStreamBasicDescription.canonical(with: format)
		NotError(ExtAudioFileSetProperty(fileRef, kExtAudioFileProperty_ClientDataFormat, SizeOf(clientDescr), &clientDescr), 51017)

		if async {
			ExtAudioFileWriteAsync(fileRef, 0, nil)
		}

		self.fileRef = fileRef
	}


	deinit {
		let status = ExtAudioFileDispose(fileRef)
		if status != noErr {
			DLOG("AudioFileWriter: close failed (\(status))")
		}
	}


	public func writeSync(frameCount: Int, buffers: AudioBufferListPtr) throws -> Int {
		var numWritten: Int = 0
		let status = write(async: false, frameCount: frameCount, buffers: buffers, numWritten: &numWritten)
		if status != noErr {
			throw AudioError.fileWrite(code: status)
		}
		return numWritten
	}


	public func writeAsync(frameCount: Int, buffers: AudioBufferListPtr) -> OSStatus {
		var numWritten: Int = 0
		return write(async: true, frameCount: frameCount, buffers: buffers, numWritten: &numWritten)
	}


	private func write(async: Bool, frameCount: Int, buffers: AudioBufferListPtr, numWritten: inout Int) -> OSStatus {
		// Despite that ExtAudioFileWrite() takes frameCount as a parameter, the actual number of samples should still be written into the buffers (why?!)
		let saveSamples = buffers[0].sampleCount
		for i in buffers.indices {
			buffers[i].sampleCount = frameCount
		}
		let status = (async ? ExtAudioFileWriteAsync : ExtAudioFileWrite)(fileRef, UInt32(frameCount), buffers.unsafePointer)
		for i in buffers.indices {
			buffers[i].sampleCount = saveSamples
		}
		if status != noErr {
			DLOG("AudioFileWriter: write failed (\(status))")
			numWritten = 0
			return status
		}
		numWritten = frameCount
		return noErr
	}
}
