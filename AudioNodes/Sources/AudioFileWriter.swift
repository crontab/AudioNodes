//
//  AudioFileWriter.swift
//  AudioNodes
//
//  Created by Hovik Melikyan on 14.08.24.
//

import Foundation
import AudioToolbox


enum AudioFileError: LocalizedError {
	case osError(_ status: OSStatus)

	var errorDescription: String? {
		switch self {
			case .osError(let status):
				return "OS Error (\(status))"
		}
	}
}


final class AudioFileWriter {

	final let url: URL
	final let format: StreamFormat
	final let fileRef: ExtAudioFileRef


	init?(url: URL, format: StreamFormat, fileSampleRate: Double, compressed: Bool, async: Bool) {
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
			return nil
		}

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


	func writeSync(frameCount: Int, buffers: AudioBufferListPtr) -> Error? {
		let status = ExtAudioFileWrite(fileRef, UInt32(frameCount), buffers.unsafePointer)
		if status != noErr {
			DLOG("AudioFileWriter: write failed (\(status))")
			return AudioFileError.osError(status)
		}
		return nil
	}


	func writeAsync(frameCount: Int, buffers: AudioBufferListPtr) -> Error? {
		let status = ExtAudioFileWriteAsync(fileRef, UInt32(frameCount), buffers.unsafePointer)
		if status != noErr {
			DLOG("AudioFileWriter: write failed (\(status))")
			return AudioFileError.osError(status)
		}
		return nil
	}
}
