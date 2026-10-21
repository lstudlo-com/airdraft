// Reads a JSON array of strings on stdin and writes the same array converted with
// the ICU "Hans-Hant" transform that ChineseScriptConverter uses for Traditional.
//   xcrun swiftc -O eval/mixed-asr/to_traditional.swift -o /tmp/to-traditional
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let strings = try JSONDecoder().decode([String].self, from: input)
let converted = strings.map { $0.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? $0 }
FileHandle.standardOutput.write(try JSONEncoder().encode(converted))
