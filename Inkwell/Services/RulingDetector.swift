import UIKit

/// Ruling line detection for paper photos. Primary: OpenCV probabilistic
/// Hough (robust against tilt, page content, faint lines). Fallback: the
/// row-profile percentile scan.
enum RulingDetector {
    /// Returns detected line y-positions in the image's point coordinates
    /// (top-origin), or nil when no plausible ruling was found.
    static func detectLines(in image: UIImage) -> [CGFloat]? {
        let hough = RulingDetectorOC.detectRulingLines(in: image) ?? []
        if hough.count >= 2 {
            return hough.map { CGFloat($0.doubleValue) }
        }
        return detectWithRowProfile(in: image)
    }

    /// Row-profile percentile fallback.
    private static func detectWithRowProfile(in image: UIImage) -> [CGFloat]? {
        guard let cg = image.cgImage else { return nil }
        let srcW = cg.width, srcH = cg.height
        guard srcW > 40, srcH > 40 else { return nil }

        // Downscale moderately: thin rules lose contrast if over-shrunk.
        let targetW = 960
        let scale = Double(targetW) / Double(srcW)
        let w = targetW
        let h = max(2, Int(Double(srcH) * scale))
        guard h > 30 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Per-row LOW-PERCENTILE luminance over the middle 70% of columns.
        // A thin dark rule makes a few pixels in its row clearly dark even
        // when interpolation dilutes it — a row mean would wash that out.
        var rowStats = [Double](repeating: 0, count: h)
        let x0 = w * 15 / 100, x1 = w * 85 / 100
        var samples = [UInt8]()
        samples.reserveCapacity((x1 - x0) / 3 + 1)
        for y in 0..<h {
            samples.removeAll(keepingCapacity: true)
            var x = x0
            while x < x1 {
                samples.append(pixels[y * w + x])
                x += 3
            }
            samples.sort()
            let idx = samples.count * 12 / 100
            rowStats[y] = Double(samples[idx])
        }

        // Two passes: strict first, relaxed fallback for faint ruling.
        for relaxed in [false, true] {
            if let rows = findLineRows(rowStats: rowStats, relaxed: relaxed) {
                // Bitmap row 0 is the image BOTTOM (CG y-up); convert to
                // top-origin page points (source pixels are points at scale 1).
                let pxToPoint = CGFloat(1.0 / scale)
                let ys = rows.map { CGFloat(h - $0) * pxToPoint }.sorted()
                if ys.count >= 2 {
                    return ys
                }
            }
        }
        return nil
    }

    /// Finds center rows of horizontal dark lines. Adaptive: a row is a line
    /// when its statistic is clearly below the neighborhood median and the
    /// neighborhood actually has contrast.
    private static func findLineRows(rowStats: [Double], relaxed: Bool) -> [Int]? {
        let h = rowStats.count
        let half = 10
        let margin = h / 50 // ignore 2% at top/bottom (paper edges, shadows)
        let contrastGate: Double = relaxed ? 6 : 12
        let dipGate: Double = relaxed ? 4 : 8

        var dark = [Bool](repeating: false, count: h)
        var window = [Double]()
        window.reserveCapacity(half * 2 + 1)
        for y in margin..<(h - margin) {
            window.removeAll(keepingCapacity: true)
            for yy in max(0, y - half)...min(h - 1, y + half) {
                window.append(rowStats[yy])
            }
            window.sort()
            let p10 = Double(window[window.count * 10 / 100])
            let p90 = Double(window[max(0, window.count * 90 / 100 - 1)])
            let median = Double(window[window.count / 2])
            let range = p90 - p10
            if range > contrastGate && rowStats[y] < median - max(dipGate, range * 0.2) {
                dark[y] = true
            }
        }

        // Group consecutive dark rows into line centers, merge near-duplicates.
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
        var filtered: [Int] = []
        for c in centers where c >= margin && c <= h - margin {
            if let last = filtered.last, c - last < 8 {
                filtered[filtered.count - 1] = (filtered.last! + c) / 2
            } else {
                filtered.append(c)
            }
        }
        // Plausibility: at least 2 lines. Filter duplicates/outliers against
        // the median spacing (printed content can add a stray dark row).
        guard filtered.count >= 2, filtered.count <= 200 else { return nil }
        var spacings: [Double] = []
        for i in 1..<filtered.count {
            spacings.append(Double(filtered[i] - filtered[i - 1]))
        }
        let medianSpacing = spacings.sorted()[spacings.count / 2]
        guard medianSpacing > 4 else { return nil }
        var kept: [Int] = [filtered[0]]
        for i in 1..<filtered.count {
            let gap = Double(filtered[i] - kept.last!)
            if gap >= medianSpacing * 0.45 {
                kept.append(filtered[i])
            } // too close to the previous line → merged duplicate, drop
        }
        guard kept.count >= 2 else { return nil }
        return kept
    }
}
