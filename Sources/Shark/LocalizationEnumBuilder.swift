import Foundation

private enum LocalizationValue: Comparable {
    enum InterpolationType {
        case uint
        case int
        case int64
        case double
        case string
        
        init(value: String) {
            if value.contains("ld") {
                self = .int64
            } else if value.contains("d") || value.contains("i") {
                self = .int
            } else if value.contains("u") {
                self = .uint
            } else if value.contains("f") {
                self = .double
            } else {
                self = .string
            }
        }
        
        var typeName: String {
            switch self {
            case .uint:
                return "UInt"
            case .int:
                return "Int"
            case .int64:
                return "Int64"
            case.double:
                return "Double"
            case .string:
                return "String"
            }
        }
    }
    
    case namespace(name: String)
    case localization(name: String, key: String, value: String)
    
    static func <(lhs: LocalizationValue, rhs: LocalizationValue) -> Bool {
        switch (lhs, rhs) {
        case (.namespace, .localization):
            return true
        case (.localization, .namespace):
            return false
        case let (.namespace(leftName), .namespace(rightName)),
             let (.localization(leftName, _, _), .localization(rightName, _, _)):
            return leftName < rightName
        }
    }
    
    func declaration(withBody body: String = "", indentLevel: Int) throws -> String {
        var result = ""
        switch self {
        case .namespace(let name):
            result += #"""
            \#(String(indentLevel: indentLevel))public enum \#(name) {
            \#(body)
            \#(String(indentLevel: indentLevel))}
            """#
        case .localization(let name, let key, let value):
            let translationComment = value.mapLines { "/// \($0)" }
            result += """
            \(translationComment.indented(withLevel: indentLevel))
            
            """
            
            let interpolatedTypes = try LocalizationValue.interpolationTypes(forValue: value)
            if interpolatedTypes.isEmpty == false {
                result += interpolatedTypes.functionDeclaration(withName: name, key: key, indentLevel: indentLevel)
            } else {
                result += #"\#(String(indentLevel: indentLevel))public static var \#(name): String { return NSLocalizedString("\#(key)", comment: "") }"#
            }
        }
        return result
    }
    
    private static func interpolationTypes(forValue value: String) throws -> [InterpolationType] {
        let regex = try NSRegularExpression(pattern: "%([0-9]*.[0-9]*(d|i|u|f|ld)|(\\d\\$)?@|d|i|u|f|ld)", options: [])
        
        let results = regex.matches(in: value, options: [], range: NSRange(location: 0, length: value.count))
        return results.map { (value as NSString).substring(with: $0.range) }.map(InterpolationType.init)
    }
}

enum LocalizationBuilderError: Error {
    case invalidLocalizableStringsFile(path: String)
    
    var localizedDescription: String {
        switch self {
        case .invalidLocalizableStringsFile(let path):
            return "Invalid .strings file at \(path)"
        }
    }
}

enum LocalizationEnumBuilder {
    static func localizationsEnumString(forFilesAtPaths paths: [String], topLevelName: String) throws -> String? {
        let termsDictionaries = try paths.compactMap({ path -> [String: String] in
            guard let termsDictionary = NSDictionary(contentsOfFile: path) as? [String: String] else {
                throw LocalizationBuilderError.invalidLocalizableStringsFile(path: path)
            }
            return termsDictionary
        })
        
        guard termsDictionaries.isEmpty == false else { return nil }
        
        let rootNode = Node(value: LocalizationValue.namespace(name: topLevelName))
        
        for termsDictionary in termsDictionaries {
            for (name, value) in termsDictionary {
                var parts = name.split(separator: ".")
                
                guard parts.isEmpty == false else { continue }
                
                let lastComponent = parts.removeLast()
                let variableName = LocalizationValue.localization(name: String(lastComponent).casenameSanitized, key: name, value: value)
                var namespaces = parts.map({ LocalizationValue.namespace(name: String($0).casenameSanitized) })
                namespaces.append(variableName)
                rootNode.add(childrenRelatively: namespaces.map(Node.init))
            }
        }
        
        rootNode.sort()
        rootNode.sanitize()
        let result = try localizationEnumString(for: rootNode)
        return result
    }
    
    private static func localizationEnumString(for node: Node<LocalizationValue>, indentLevel: Int = 0) throws -> String {
        switch node.value {
        case .namespace:
            let childrenString = try node.children.map { try localizationEnumString(for: $0, indentLevel: indentLevel + 1) }
            return try node.value.declaration(withBody: childrenString.joined(separator: "\n\n"), indentLevel: indentLevel)
        case .localization:
            return try node.value.declaration(indentLevel: indentLevel)
        }
    }
}

extension Array where Element == LocalizationValue.InterpolationType {
    func functionDeclaration(withName name: String, key: String, indentLevel: Int) -> String {
        let variableName = "value"
        let arguments = zip((1...count), self).map { tuple -> String in
            let (idx, interpolationType) = tuple
            return "_ \(variableName)\(idx): \(interpolationType.typeName)"
        }
        let argumentsString = arguments.joined(separator: ",")
        let formatValuesString = (1...count).map { "\(variableName)\($0)"}.joined(separator: ", ")

        return #"""
        \#(String(indentLevel: indentLevel))public static func \#(name)(\#(argumentsString)) -> String {
        \#(String(indentLevel:indentLevel + 1))return String(format: NSLocalizedString("\#(key)", comment: ""), \#(formatValuesString))
        \#(String(indentLevel: indentLevel))}
        """#
    }
}

private extension Node where Element == LocalizationValue {
    func sanitize() {
        //If two children have the same name, or if a children has the same name with a parent, underscore
        var modified = false
        repeat {
            modified = false
            var countedSet = CountedSet<String>()
            for child in children {
                for _ in 0..<countedSet.count(for: child.name) {
                    child.underscoreName()
                    modified = true
                }
                countedSet.add(child.name)
                if name == child.name {
                    child.underscoreName()
                    modified = true
                }
            }
        } while modified
        
        children.forEach { $0.sanitize() }
    }
    
    private var name: String {
        switch value {
        case .localization(let name, _, _), .namespace(let name):
            return name
        }
    }
    
    private func underscoreName() {
        switch value {
        case .localization(let name, let key, let value):
            self.value = .localization(name: name.underscored, key: key, value: value)
        case .namespace(let name):
            self.value = .namespace(name: name.underscored)
        }
    }
}
