import Foundation
import XcodeProj
import PathKit

enum PBXFilePathError: String, Error {
    case cannotResolvePath
}

struct XcodeProjectHelper {
    struct ResourcePaths {
        let localizationPaths: [String]
        let assetsPaths: [String]
    }
    
    private let projectPath: Path
    private let xcodeproj: XcodeProj
    private let targetName: String?
    private let locale: String
    
    init(parseResult: Parser.Result) throws {
        projectPath = Path(parseResult.projectPath)
        xcodeproj = try XcodeProj(path: projectPath)
        targetName = parseResult.targetName
        locale = parseResult.locale
    }
    
    func resourcePaths() throws -> ResourcePaths {
        let eligibleTargets = xcodeproj.pbxproj.nativeTargets.filter({ $0.productType == .application || $0.productType == .framework })
        let eligibleTargetsHelpString = "The available targets are:\n\(eligibleTargets.map({ "- \($0.name)" }).joined(separator: "\n"))"
        let selectedTarget: PBXNativeTarget
        
        if let targetName = targetName {
            guard let target = eligibleTargets.first(where: { $0.name == targetName }) else {
                print("No target found with name \(targetName).\n\(eligibleTargetsHelpString)")
                exit(EXIT_FAILURE)
            }
            
            selectedTarget = target
        } else {
            guard eligibleTargets.count == 1 else {
                print("Multiple application targets found, please specify the target by using the --target flag.\n\(eligibleTargetsHelpString)")
                exit(EXIT_FAILURE)
            }
            
            selectedTarget = eligibleTargets[0]
        }
        
        guard let targetResourcesFiles = try selectedTarget.resourcesBuildPhase()?.files else {
            print("Cannot locate the resources build phase in the target")
            exit(EXIT_FAILURE)
        }
        
        var localizationPaths: [String] = []
        var assetPaths: [String] = []
        
        let allPaths = try targetResourcesFiles.compactMap { $0.file }.flatMap { try paths(for: $0) }
        for path in allPaths {
            switch path.pathExtension {
            case "xcassets":
                assetPaths.append(path)
            case "strings" where path.pathComponents.contains("\(locale).lproj"):
                localizationPaths.append(path)
            default:
                break
            }
        }

        return ResourcePaths(localizationPaths: localizationPaths, assetsPaths: assetPaths)
    }
 
    private func paths(for fileElement: PBXFileElement) throws -> [String] {
        guard let filePath = try fileElement.fullPath(sourceRoot: projectPath.parent()) else {
            throw PBXFilePathError.cannotResolvePath
        }
        
        if let variant = fileElement as? PBXVariantGroup {
            return variant.children.compactMap { filePath.string.appendingPathComponent($0.path!) }
        } else {
            return [filePath.string]
        }
    }
}
