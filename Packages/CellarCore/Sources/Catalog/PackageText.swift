import Foundation

/// The single normalisation applied to searchable text.
///
/// Applied once per record at index build and once per query at search time.
/// Doing it identically on both sides is what lets matching be a raw byte scan:
/// no case comparison, no Unicode work, no per-keystroke `String` allocation
/// (package-search PS2).
public enum PackageText {
    /// Lowercased, diacritic-folded, ASCII-only bytes with runs of anything else
    /// collapsed to a single space, trimmed.
    ///
    /// Characters with no ASCII equivalent become separators rather than being
    /// dropped, so `115浏览器` normalises to `115` and not to `115browser`-style
    /// nonsense that would match queries it has nothing to do with.
    public static func normalize(_ input: String) -> [UInt8] {
        // A fixed POSIX locale: folding is locale-sensitive, and a Turkish
        // locale would famously lowercase `I` to `ı`.
        let folded = input.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: posix
        )

        var bytes: [UInt8] = []
        bytes.reserveCapacity(folded.utf8.count)
        var pendingSeparator = false

        for byte in folded.utf8 {
            let isDigit = byte >= 0x30 && byte <= 0x39
            let isLower = byte >= 0x61 && byte <= 0x7A
            let isUpper = byte >= 0x41 && byte <= 0x5A

            if isDigit || isLower || isUpper {
                if pendingSeparator, !bytes.isEmpty { bytes.append(0x20) }
                pendingSeparator = false
                // `folding(.caseInsensitive)` already lowercased ASCII, but a
                // byte-level fallback costs nothing and removes the assumption.
                bytes.append(isUpper ? byte + 0x20 : byte)
            } else {
                pendingSeparator = true
            }
        }

        return bytes
    }

    /// The normalised form as a `String`, for assertions and display.
    public static func normalizedString(_ input: String) -> String {
        // `normalize` guarantees ASCII bytes, so this decode cannot fail and a
        // failable initialiser would only add an optional nobody can hit.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: normalize(input), as: UTF8.self)
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}
