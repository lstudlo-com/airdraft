import Foundation

/// multipart/form-data body with text fields and one WAV file, as the
/// transcription APIs expect.
struct MultipartForm {
    let boundary = "Boundary-\(UUID().uuidString)"
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func body(fields: [(String, String)], wav: Data, fileField: String = "file", jsonFields: Set<String> = []) -> Data {
        var body = Data()
        for (name, value) in fields {
            let contentType = jsonFields.contains(name) ? "Content-Type: application/json\r\n" : ""
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\(contentType)\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
