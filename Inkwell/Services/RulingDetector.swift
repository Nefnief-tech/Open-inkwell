import UIKit

/// Detects horizontal ruling lines in a paper photo so text lines can be
/// snapped to the paper's actual lines (photos have perspective — a single
/// uniform spacing can't follow the real ruling over many lines).
enum RulingDetector {
    /// Returns detected line y-positions in the image's point coordinates
    /// (top-origin), or nil when no plausible ruling was found.
    static func detectLines(in image: UIImage) -> [CGFloat]? {
        guard let cg = image.cgImage else { return nil }
        let srcW = cg.width, srcH = cg.height
        guard srcW > 40, srcH > 40 else { return nil }

        // Downscale for speed: ~480 px wide grayscale.
        let targetW = 480
        let scale = Double(targetW) / Double(srcW)
        let w = targetW
        let h = max(2, Int(Double(srcH) * scale))
        guard h > 20 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Mean luminance per row, sampled over the middle 60% of columns
        // (avoids edge shadows and binder margins).
        var rowMeans = [Double](repeating: 0, count: h)
        let x0 = w * 20 / 100, x1 = w * 80 / 100
        for y in 0..<h {
            var sum = 0
            var n = 0
            var x = x0
            while x < x1 {
                sum += Int(pixels[y * w + x])
                n += 1
                x += 2
            }
            rowMeans[y] = Double(sum) / Double(max(1, n))
        }

        // Adaptive threshold: a row is "dark" when clearly below its
        // neighborhood's mean, and only when the neighborhood has contrast.
        let half = 8
        var dark = [Bool](repeating: false, count: h)
        for y in 0..<h {
            let lo = max(0, y - half), hi = min(h - 1, y + half)
            var m = 0.0
            var mn = rowMeans[lo], mx = rowMeans[lo]
            for yy in lo...hi {
                m += rowMeans[yy]
                mn = min(mn, rowMeans[yy])
                mx = max(mx, rowMeans[yy])
            }
            m /= Double(hi - lo + 1)
            let contrast = mx - mn
            if contrast > 10 && rowMeans[y] < m - min(9, contrast * 0.35) {
                dark[y] = true
            }
        }

        // Group consecutive dark rows into line centers.
        var centers: [Int] = []
        var y = 0
        while y < h {
            if dark[y] {
                var end = y
                while end + 1 < h && dark[end + 1] { end += 1 }
                centers.append((y + end) / 2)
                y = end + 1
            } else {
                y += 1
            }
        }

        // Merge near-duplicates, drop edge artifacts.
        var filtered: [Int] = []
        for c in centers where c >= 2 && c <= h - 3 {
            if let last = filtered.last, c - last < 6 {
                filtered[filtered.count - 1] = (filtered.last! + c) / 2
            } else {
                filtered.append(c)
            }
        }
        guard filtered.count >= 2, filtered.count <= 200 else { return nil }

        // Bitmap row 0 is the image BOTTOM (CG y-up); convert to top-origin
        // page points. Downscale factor: px → points.
        let pxToPoint = 1.0 / scale
        let ys = filtered.map { CGFloat(h - $0) * pxToPoint }.sorted()
        return ys
    }
}
