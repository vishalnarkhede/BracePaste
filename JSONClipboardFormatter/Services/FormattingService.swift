import Foundation

/// Coordinates JSON extraction/formatting off the main thread and serializes work.
actor FormattingService {
    private var currentTask: Task<JSONProcessingResult, Never>?
    private var generation: UInt64 = 0

    func format(
        input: String,
        indentation: IndentationStyle
    ) async -> JSONProcessingResult {
        generation &+= 1
        let myGeneration = generation

        currentTask?.cancel()

        let task = Task<JSONProcessingResult, Never> {
            if Task.isCancelled {
                return .failure(message: "Cancelled", originalInput: input)
            }
            return JSONExtractor.process(input, indentation: indentation)
        }
        currentTask = task

        let result = await task.value
        if myGeneration != generation {
            return .failure(message: "Cancelled", originalInput: input)
        }
        return result
    }

    func cancel() {
        generation &+= 1
        currentTask?.cancel()
        currentTask = nil
    }
}
