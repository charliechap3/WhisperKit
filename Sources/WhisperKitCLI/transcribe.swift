//  For licensing see accompanying LICENSE.md file.
//  Copyright © 2024 Argmax, Inc. All rights reserved.

import ArgumentParser
import CoreML
import Foundation

import WhisperKit

@available(macOS 14, iOS 17, *)
@main
struct WhisperKitCLI: AsyncParsableCommand {
    @Option(help: "Path to audio file")
    var audioPath: String = "./Tests/WhisperKitTests/Resources/jfk.wav"

    @Option(help: "Path of model files")
    var modelPath: String = "./Models/whisperkit-coreml/openai_whisper-tiny"

    @Option(help: "Compute units for audio encoder model with {all,cpuOnly,cpuAndGPU,cpuAndNeuralEngine,random}")
    var audioEncoderComputeUnits: ComputeUnits = .cpuAndNeuralEngine

    @Option(help: "Compute units for text decoder model with {all,cpuOnly,cpuAndGPU,cpuAndNeuralEngine,random}")
    var textDecoderComputeUnits: ComputeUnits = .cpuAndNeuralEngine

    @Flag(help: "Verbose mode")
    var verbose: Bool = false

    @Option(help: "Task to perform (transcribe or translate)")
    var task: String = "transcribe"

    @Option(help: "Language spoken in the audio")
    var language: String?

    @Option(help: "Temperature to use for sampling")
    var temperature: Float = 0

    @Option(help: "Temperature to increase on fallbacks during decoding")
    var temperatureIncrementOnFallback: Float = 0.2

    @Option(help: "Number of times to increase temperature when falling back during decoding")
    var temperatureFallbackCount: Int = 5

    @Option(help: "Number of candidates when sampling with non-zero temperature")
    var bestOf: Int = 5

    @Flag(help: "Force initial prompt tokens based on language, task, and timestamp options")
    var usePrefillPrompt: Bool = false

    @Flag(help: "Use decoder prefill data for faster initial decoding")
    var usePrefillCache: Bool = false

    @Flag(help: "Skip special tokens in the output")
    var skipSpecialTokens: Bool = false

    @Flag(help: "Force no timestamps when decoding")
    var withoutTimestamps: Bool = false

    @Option(help: "Gzip compression ratio threshold for decoding failure")
    var compressionRatioThreshold: Float?

    @Option(help: "Average log probability threshold for decoding failure")
    var logprobThreshold: Float?

    @Option(help: "Probability threshold to consider a segment as silence")
    var noSpeechThreshold: Float?

    @Flag(help: "Output a report of the results")
    var report: Bool = false

    @Option(help: "Directory to save the report")
    var reportPath: String = "."

    func transcribe(audioPath: String, modelPath: String) async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            fatalError("Resource path does not exist \(modelPath)")
        }

        let computeOptions = ModelComputeOptions(
            audioEncoderCompute: audioEncoderComputeUnits.asMLComputeUnits,
            textDecoderCompute: textDecoderComputeUnits.asMLComputeUnits
        )

        let whisperKit = try await WhisperKit(
            modelFolder: modelPath,
            computeOptions: computeOptions,
            verbose: verbose,
            logLevel: .debug
        )

        let options = DecodingOptions(
            verbose: verbose,
            task: .transcribe,
            language: language,
            temperature: temperature,
            temperatureIncrementOnFallback: temperatureIncrementOnFallback,
            temperatureFallbackCount: temperatureFallbackCount,
            topK: bestOf,
            usePrefillPrompt: usePrefillPrompt,
            usePrefillCache: usePrefillCache,
            skipSpecialTokens: skipSpecialTokens,
            withoutTimestamps: withoutTimestamps,
            compressionRatioThreshold: compressionRatioThreshold,
            logProbThreshold: logprobThreshold,
            noSpeechThreshold: noSpeechThreshold
        )

        let transcribeResult = try await whisperKit.transcribe(audioPath: audioPath, decodeOptions: options)

        let transcription = transcribeResult?.text ?? "Transcription failed"

        if report, let result = transcribeResult {
            let audioFileName = URL(fileURLWithPath: audioPath).lastPathComponent.components(separatedBy: ".").first!

            // Write SRT (SubRip Subtitle Format) for the transcription
            let srtReportWriter = WriteSRT(outputDir: reportPath)
            let savedSrtReport = srtReportWriter.write(result: result, to: audioFileName)
            if verbose {
                switch savedSrtReport {
                case let .success(reportPath):
                    print("\n\nSaved SRT Report: \n\n\(reportPath)\n")
                case let .failure(error):
                    print("\n\nCouldn't save report: \(error)\n")
                }
            }

            // Write JSON for all metadata
            let jsonReportWriter = WriteJSON(outputDir: reportPath)
            let savedJsonReport = jsonReportWriter.write(result: result, to: audioFileName)
            if verbose {
                switch savedJsonReport {
                case let .success(reportPath):
                    print("\n\nSaved JSON Report: \n\n\(reportPath)\n")
                case let .failure(error):
                    print("\n\nCouldn't save report: \(error)\n")
                }
            }
        }

        if verbose {
            print("\n\nTranscription: \n\n\(transcription)\n")
        } else {
            print(transcription)
        }
    }

    func run() async throws {
        let audioURL = URL(fileURLWithPath: audioPath)

        if verbose {
            print("Transcribing audio at \(audioURL)")
        }

        try await transcribe(audioPath: audioPath, modelPath: modelPath)
    }
}

enum ComputeUnits: String, ExpressibleByArgument, CaseIterable {
    case all, cpuAndGPU, cpuOnly, cpuAndNeuralEngine, random
    var asMLComputeUnits: MLComputeUnits {
        switch self {
        case .all: return .all
        case .cpuAndGPU: return .cpuAndGPU
        case .cpuOnly: return .cpuOnly
        case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
        case .random: return Bool.random() ? .cpuAndGPU : .cpuAndNeuralEngine
        }
    }
}
