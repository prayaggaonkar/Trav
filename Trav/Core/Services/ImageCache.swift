import Foundation
import UIKit

/// Memory + URLCache-backed image loader used by `CachedAsyncImage` / `RemoteImage`.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 64 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "trav.images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) {
            return cached
        }

        if url.isFileURL {
            guard let data = try? Data(contentsOf: url),
                  var image = UIImage(data: data) else { return nil }
            if let maxPixelSize, max(image.size.width, image.size.height) > maxPixelSize {
                image = downsample(image, maxPixelSize: maxPixelSize) ?? image
            }
            memory.setObject(image, forKey: key, cost: data.count)
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                var image = UIImage(data: data)
            else { return nil }

            if let maxPixelSize, max(image.size.width, image.size.height) > maxPixelSize {
                image = downsample(image, maxPixelSize: maxPixelSize) ?? image
            }

            memory.setObject(image, forKey: key, cost: data.count)
            return image
        } catch {
            return nil
        }
    }

    private func downsample(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage? {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 0 else { return image }
        let scale = maxPixelSize / maxSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
