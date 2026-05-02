import Foundation

enum HomeLoggingTextMatch {
    nonisolated static func rowItemMatchScore(rowText: String, itemName: String) -> Double {
        let rowTokens = Set(normalizedMatchTokens(from: rowText))
        let itemTokens = Set(normalizedMatchTokens(from: itemName))
        guard !rowTokens.isEmpty, !itemTokens.isEmpty else { return 0.0 }

        let exactIntersection = rowTokens.intersection(itemTokens).count
        var weightedIntersection = Double(exactIntersection)

        // Typo-tolerant fuzzy token match (e.g. "cofeee" ~= "coffee") while keeping one-to-one alignment.
        var unmatchedItemTokens = itemTokens.subtracting(rowTokens)
        for rowToken in rowTokens.subtracting(itemTokens) {
            var bestItemToken: String?
            var bestSimilarity = 0.0
            for itemToken in unmatchedItemTokens {
                let similarity = fuzzyTokenSimilarity(rowToken, itemToken)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestItemToken = itemToken
                }
            }
            if let bestItemToken, bestSimilarity >= 0.80 {
                weightedIntersection += 0.75
                unmatchedItemTokens.remove(bestItemToken)
            }
        }

        let union = Double(rowTokens.count + itemTokens.count) - weightedIntersection
        guard union > 0 else { return 0.0 }

        let jaccard = weightedIntersection / union
        let rowCoverage = weightedIntersection / Double(rowTokens.count)
        let itemCoverage = weightedIntersection / Double(itemTokens.count)

        var score = max(jaccard, max(rowCoverage * 0.72, itemCoverage * 0.88))

        if itemCoverage == 1.0 || rowCoverage == 1.0 {
            score += 0.15
        }

        let normalizedRow = rowTokens.sorted().joined(separator: " ")
        let normalizedItem = itemTokens.sorted().joined(separator: " ")
        if normalizedRow.contains(normalizedItem) || normalizedItem.contains(normalizedRow) {
            score += 0.10
        }

        return min(score, 1.0)
    }

    nonisolated static func normalizedRowText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private static func fuzzyTokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1.0
        }
        if lhs.count < 3 || rhs.count < 3 {
            return 0.0
        }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count))
        }

        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0.0 }
        return max(0, 1.0 - Double(distance) / Double(maxLength))
    }

    nonisolated private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs {
            return 0
        }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        if lhsChars.isEmpty {
            return rhsChars.count
        }
        if rhsChars.isEmpty {
            return lhsChars.count
        }

        var previous = Array(0...rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = Array(repeating: 0, count: rhsChars.count + 1)
            current[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsChar == rhsChar ? 0 : 1)
                current[rhsIndex + 1] = min(insertion, min(deletion, substitution))
            }
            previous = current
        }

        return previous[rhsChars.count]
    }

    nonisolated private static func normalizedMatchTokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}
