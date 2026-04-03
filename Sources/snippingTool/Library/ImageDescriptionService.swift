import CoreGraphics
import CoreImage
import Foundation
import MLXLMCommon
import MLXVLM

actor ImageDescriptionService {
    private static let modelID = "mlx-community/FastVLM-0.5B-bf16"
    private var modelContainer: ModelContainer?

    private func getModelContainer() async throws -> ModelContainer {
        if let modelContainer { return modelContainer }
        let container = try await loadModelContainer(id: Self.modelID)
        modelContainer = container
        return container
    }

    func describeImage(_ image: CGImage) async -> String {
        do {
            let container = try await getModelContainer()
            let ciImage = CIImage(cgImage: image)
            let session = ChatSession(container)
            let prompt = """
                Describe this screenshot in one short sentence. \
                Focus on the main content, app, or activity visible. \
                Do NOT start with "This screenshot shows" or similar phrasing. \
                Do NOT mention that it is a screenshot. \
                Just directly describe the content.
                """
            let result = try await session.respond(to: prompt, image: .ciImage(ciImage))
            let description = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty { return description }
        } catch {
            return "Description unavailable: \(error.localizedDescription)"
        }
        return ""
    }
}
