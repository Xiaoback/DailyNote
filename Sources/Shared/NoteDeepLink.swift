import Foundation

struct NoteDeepLink: Equatable {
    enum Destination { case quick, editor }
    var day: String
    var blockID: UUID?
    var destination: Destination

    static func quick(day: String, blockID: UUID? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "daily-note"
        components.host = "quick"
        components.queryItems = [URLQueryItem(name: "day", value: day)]
        if let blockID { components.queryItems?.append(URLQueryItem(name: "block", value: blockID.uuidString)) }
        return components.url!
    }

    static func parse(_ url: URL, today: String = DayKey.string()) -> NoteDeepLink? {
        guard url.scheme?.lowercased() == "daily-note", let host = url.host?.lowercased(),
              ["quick", "today", "editor"].contains(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let day = components.queryItems?.first(where: { $0.name == "day" })?.value ?? today
        guard DayKey.isValid(day) else { return nil }
        let blockID = components.queryItems?.first(where: { $0.name == "block" })?.value.flatMap(UUID.init(uuidString:))
        return NoteDeepLink(day: day, blockID: blockID, destination: host == "editor" ? .editor : .quick)
    }
}
