import Foundation

final class SceneAnalyzer {
    var columns: Int = 36

    /// Set of segmentation label IDs considered walkable.
    /// Default: common COCO panoptic stuff IDs for ground surfaces.
    /// road=21, sidewalk=52, terrain=94, floor=4, carpet=29, rug=131, pavement/road(alt)=7, ground=14
    var walkableIDs: Set<UInt8> = [4, 7, 14, 21, 29, 52, 94, 131]

    /// Fraction of image height from bottom considered ground region for traversability.
    var groundRegionFraction: Float = 0.6

    /// Fraction of image height from bottom used for discontinuity detection.
    var discontinuityRegionFraction: Float = 0.4

    /// Minimum normalized gradient magnitude (0-1) to count as discontinuity.
    var discontinuityThreshold: Float = 0.08

    /// Minimum absolute gradient to consider (filters out noise on smooth surfaces).
    var discontinuityMinAbsGradient: Float = 0.3

    func analyze(
        depthData: [Float],
        depthWidth: Int,
        depthHeight: Int,
        segLabels: [UInt8],
        segWidth: Int,
        segHeight: Int,
        cameraHFOV: Float
    ) -> SceneUnderstanding {
        let cols = columns

        // 1. Column bearings
        let bearings = (0..<cols).map { i in
            (Float(i) / Float(cols) - 0.5) * cameraHFOV
        }

        // 2. Traversability + 3. Obstacle distance
        var traversability = [Float](repeating: 0, count: cols)
        var obstacleDistance = [Float](repeating: Float.infinity, count: cols)

        let segGroundStartRow = Int(Float(segHeight) * (1.0 - groundRegionFraction))

        for col in 0..<cols {
            let segXStart = col * segWidth / cols
            let segXEnd = (col + 1) * segWidth / cols
            guard segXEnd > segXStart else { continue }

            // Traversability: bottom groundRegionFraction of seg image
            var walkableCount = 0
            var totalCount = 0

            for row in segGroundStartRow..<segHeight {
                for x in segXStart..<segXEnd {
                    totalCount += 1
                    if walkableIDs.contains(segLabels[row * segWidth + x]) {
                        walkableCount += 1
                    }
                }
            }

            traversability[col] = totalCount > 0 ? Float(walkableCount) / Float(totalCount) : 0

            // Obstacle distance: scan depth column bottom to top, find first non-walkable
            let depthXStart = col * depthWidth / cols
            let depthXEnd = (col + 1) * depthWidth / cols
            let depthXMid = (depthXStart + depthXEnd) / 2
            guard depthXMid < depthWidth else { continue }

            let depthGroundStartRow = Int(Float(depthHeight) * (1.0 - groundRegionFraction))

            for row in stride(from: depthHeight - 1, through: depthGroundStartRow, by: -1) {
                // Map depth pixel to seg pixel
                let segRow = row * segHeight / depthHeight
                let segX = depthXMid * segWidth / depthWidth

                let segIdx = segRow * segWidth + min(segX, segWidth - 1)
                let isWalkable = walkableIDs.contains(segLabels[segIdx])

                if !isWalkable {
                    obstacleDistance[col] = depthData[row * depthWidth + depthXMid]
                    break
                }
            }
        }

        // 4. Surface discontinuities
        var discontinuities = [Discontinuity]()

        let discStartRow = Int(Float(depthHeight) * (1.0 - discontinuityRegionFraction))

        for col in 0..<cols {
            let depthXStart = col * depthWidth / cols
            let depthXEnd = (col + 1) * depthWidth / cols
            let depthXMid = (depthXStart + depthXEnd) / 2
            guard depthXMid < depthWidth else { continue }

            // Extract vertical depth profile (bottom up)
            var profile = [Float]()
            for row in stride(from: depthHeight - 1, through: discStartRow, by: -1) {
                profile.append(depthData[row * depthWidth + depthXMid])
            }

            guard profile.count >= 2 else { continue }

            // Compute gradients
            var gradients = [Float]()
            for i in 1..<profile.count {
                gradients.append(profile[i] - profile[i - 1])
            }

            // Find max absolute gradient for normalization
            let maxAbsGradient = gradients.map { abs($0) }.max() ?? 0
            guard maxAbsGradient > 0 else { continue }

            // Compute median absolute gradient to detect outliers vs uniform slopes
            let sortedAbsGradients = gradients.map { abs($0) }.sorted()
            let medianGrad = sortedAbsGradients[sortedAbsGradients.count / 2]

            // Find strongest discontinuity (non-maximum suppression: keep nearest = lowest index)
            var bestIdx = -1
            var bestAbsGrad: Float = 0

            for i in 0..<gradients.count {
                let absG = abs(gradients[i])
                // Must exceed absolute minimum AND be significantly above median
                let isOutlier = medianGrad > 0 ? (absG / medianGrad) > 3.0 : absG > discontinuityMinAbsGradient
                if absG >= discontinuityMinAbsGradient && isOutlier {
                    let normalized = absG / maxAbsGradient
                    if normalized >= discontinuityThreshold && absG > bestAbsGrad {
                        if bestIdx == -1 {
                            bestIdx = i
                            bestAbsGrad = absG
                        }
                    }
                }
            }

            if bestIdx >= 0 {
                let grad = gradients[bestIdx]
                let normalized = abs(grad) / maxAbsGradient
                let direction: DiscontinuityDir = grad > 0 ? .dropaway : .riseup
                // Depth at this point (profile is bottom-up, so index maps to row)
                let depthAtDisc = profile[bestIdx]

                discontinuities.append(Discontinuity(
                    column: col,
                    bearing: bearings[col],
                    relativeDepth: depthAtDisc,
                    magnitude: normalized,
                    direction: direction
                ))
            }
        }

        // 5. Ground plane ratio
        var totalGroundPixels = 0
        var walkableGroundPixels = 0

        for row in segGroundStartRow..<segHeight {
            for x in 0..<segWidth {
                totalGroundPixels += 1
                if walkableIDs.contains(segLabels[row * segWidth + x]) {
                    walkableGroundPixels += 1
                }
            }
        }

        let groundPlaneRatio = totalGroundPixels > 0 ? Float(walkableGroundPixels) / Float(totalGroundPixels) : 0

        return SceneUnderstanding(
            columns: cols,
            traversability: traversability,
            obstacleDistance: obstacleDistance,
            discontinuities: discontinuities,
            groundPlaneRatio: groundPlaneRatio,
            columnBearings: bearings
        )
    }
}
