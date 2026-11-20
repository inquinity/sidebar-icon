/// Four-character type codes in this project's range: `S` plus three base-36 characters
/// (`0`–`9`, then `A`–`Z`), research R7.
public enum OSTypeCode {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Number of codes in the range, `S000` through `SZZZ`.
    static let capacity = 36 * 36 * 36

    public static func isValid(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count == 4, chars[0] == "S" else { return false }
        return chars.dropFirst().allSatisfy { digits.contains($0) }
    }

    static func code(at index: Int) -> String {
        precondition((0..<capacity).contains(index))
        let a = digits[index / (36 * 36)]
        let b = digits[(index / 36) % 36]
        let c = digits[index % 36]
        return "S\(a)\(b)\(c)"
    }
}

public enum OSTypeAllocationError: Error, Sendable, Equatable {
    case exhausted
}

/// Hands out unused codes, starting at `S001`. Codes still referenced by the ledger or by other
/// mappings are passed in `inUse` and never reissued.
public enum OSTypeAllocator {
    public static func allocate(_ count: Int, excluding inUse: Set<String>) throws -> [String] {
        var result: [String] = []
        var index = 1
        while result.count < count {
            guard index < OSTypeCode.capacity else { throw OSTypeAllocationError.exhausted }
            let code = OSTypeCode.code(at: index)
            if !inUse.contains(code) {
                result.append(code)
            }
            index += 1
        }
        return result
    }
}
