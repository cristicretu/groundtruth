import CoreGraphics

public struct DepthMap: Sendable {
    public let width: Int
    public let height: Int
    public let data: [Float]
    public let timestamp: Double
    public let minDepth: Float
    public let maxDepth: Float

    public init(width: Int, height: Int, data: [Float], timestamp: Double) {
        precondition(data.count == width * height, "Data size must match width * height")
        self.width = width
        self.height = height
        self.data = data
        self.timestamp = timestamp

        var lo: Float = .infinity
        var hi: Float = -.infinity
        for v in data {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        self.minDepth = lo
        self.maxDepth = hi
    }

    /// Lookup depth at pixel coordinates. Returns `.infinity` for out-of-bounds.
    public func depth(atPixelX px: Int, py: Int) -> Float {
        guard px >= 0, px < width, py >= 0, py < height else { return .infinity }
        return data[py * width + px]
    }

    /// Lookup depth at normalized coordinates (0-1) with bilinear interpolation.
    public func depth(atX x: Float, y: Float) -> Float {
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return .infinity }

        let fx = x * Float(width - 1)
        let fy = y * Float(height - 1)

        let x0 = Int(fx)
        let y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)

        let xFrac = fx - Float(x0)
        let yFrac = fy - Float(y0)

        let d00 = data[y0 * width + x0]
        let d10 = data[y0 * width + x1]
        let d01 = data[y1 * width + x0]
        let d11 = data[y1 * width + x1]

        let top = d00 * (1 - xFrac) + d10 * xFrac
        let bottom = d01 * (1 - xFrac) + d11 * xFrac

        return top * (1 - yFrac) + bottom * yFrac
    }

    /// Average depth in a normalized rect, skipping `.infinity` values.
    public func averageDepth(in rect: CGRect) -> Float {
        let startX = max(0, Int(rect.minX * CGFloat(width)))
        let endX = min(width, Int(ceil(rect.maxX * CGFloat(width))))
        let startY = max(0, Int(rect.minY * CGFloat(height)))
        let endY = min(height, Int(ceil(rect.maxY * CGFloat(height))))

        guard startX < endX, startY < endY else { return .infinity }

        var sum: Float = 0
        var count = 0

        for py in startY..<endY {
            for px in startX..<endX {
                let v = data[py * width + px]
                if v.isFinite {
                    sum += v
                    count += 1
                }
            }
        }

        return count > 0 ? sum / Float(count) : .infinity
    }
}
