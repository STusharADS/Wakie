//
//  CityPhotoFetcher.swift
//  Wakie
//
//  Finds a photo of a city online for its World Clock card, using Wikipedia's free
//  page-summary API (no account or key needed). People can still pick their own photo.
//

import Foundation
import UIKit

nonisolated enum CityPhotoFetcher {
    private struct Summary: Decodable {
        struct Image: Decodable { let source: String }
        let type: String?
        let thumbnail: Image?
        let originalimage: Image?
    }

    /// Downloads a photo for the city and saves it as `<file>` in the photos folder.
    /// Returns `true` on success.
    static func fetchAndSave(name: String, country: String, file: String) async -> Bool {
        guard let data = await photoData(name: name, country: country),
              let image = UIImage(data: data),
              let jpeg = image.downscaled(maxDimension: 900).jpegData(compressionQuality: 0.85) else { return false }
        return (try? jpeg.write(to: WorldCity.photosDirectory.appending(path: file))) != nil
    }

    /// Tries "Naples", then "Naples, Italy", so ambiguous names still find the right place.
    private static func photoData(name: String, country: String) async -> Data? {
        var titles = [name]
        if !country.isEmpty { titles.append("\(name), \(country)") }
        for title in titles {
            guard let summary = await summary(for: title), summary.type != "disambiguation",
                  let thumbnail = summary.thumbnail?.source else { continue }
            // Ask for a sharper thumbnail than the default (~330 px), falling back if that size isn't offered.
            let sharper = thumbnail.replacingOccurrences(of: #"/\d+px-"#, with: "/960px-", options: .regularExpression)
            let candidates = [sharper, thumbnail]
            for candidate in candidates {
                guard let url = URL(string: candidate), let data = await download(url) else { continue }
                return data
            }
        }
        return nil
    }

    private static func summary(for title: String) async -> Summary? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
              let data = await download(url) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Wikipedia asks API clients to identify themselves.
        request.setValue("Wakie/1.0 (iOS alarm app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
