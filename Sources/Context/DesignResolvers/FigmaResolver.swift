import Foundation

struct FigmaResolver: AppContextResolver {
    let supportedBundleIds = ["com.figma.Desktop"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        // Figma window titles follow: "File Name — Page Name — Figma"
        // e.g.: "Design System — Components — Figma"

        let components = windowTitle.components(separatedBy: " — ")

        var fileName: String?
        var pageName: String?

        if components.count >= 3 {
            fileName = components[0].trimmingCharacters(in: .whitespaces)
            pageName = components[1].trimmingCharacters(in: .whitespaces)
        } else if components.count == 2, components.last == "Figma" {
            fileName = components[0].trimmingCharacters(in: .whitespaces)
        } else {
            fileName = windowTitle.replacingOccurrences(of: " — Figma", with: "")
        }

        return ResolvedContext(
            contextType: .design,
            designFileName: fileName,
            designPageName: pageName
        )
    }
}
