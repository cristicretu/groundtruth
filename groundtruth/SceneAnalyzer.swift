import Foundation

final class SceneAnalyzer {
    var columns: Int = 36

    /// Set of segmentation label IDs considered walkable.
    /// DETR COCO panoptic class IDs for ground/floor surfaces:
    /// 101=carpet, 111=dirt, 114=floor-marble, 115=floor-other, 116=floor-stone,
    /// 117=floor-tile, 118=floor-wood, 124=grass, 125=gravel, 126=ground-other,
    /// 131=mat, 136=mud, 140=pavement, 144=platform, 145=playingfield,
    /// 147=railroad, 149=road, 152=rug, 154=sand, 161=stairs
    var walkableIDs: Set<UInt8> = [
        101, 111, 114, 115, 116, 117, 118, 124, 125, 126,
        131, 136, 140, 144, 145, 147, 149, 152, 154, 161
    ]

    /// Raw depth value above which a pixel is considered sky/background and ignored.
    var skyDepthThreshold: Float = 0.95

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

        for col in 0..<cols {
            let segXStart = col * segWidth / cols
            let segXEnd = (col + 1) * segWidth / cols
            guard segXEnd > segXStart else { continue }

            // Traversability: scan ALL rows, any walkable pixel counts
            var walkableCount = 0
            var totalCount = 0

            for row in 0..<segHeight {
                for x in segXStart..<segXEnd {
                    totalCount += 1
                    if walkableIDs.contains(segLabels[row * segWidth + x]) {
                        walkableCount += 1
                    }
                }
            }

            traversability[col] = totalCount > 0 ? Float(walkableCount) / Float(totalCount) : 0

            // Obstacle distance: scan bottom to top, find first non-walkable non-sky pixel
            let depthXStart = col * depthWidth / cols
            let depthXEnd = (col + 1) * depthWidth / cols
            let depthXMid = (depthXStart + depthXEnd) / 2
            guard depthXMid < depthWidth else { continue }

            for row in stride(from: depthHeight - 1, through: 0, by: -1) {
                let depthVal = depthData[row * depthWidth + depthXMid]

                // Skip sky/background pixels
                if depthVal > skyDepthThreshold { continue }

                // Map depth pixel to seg pixel
                let segRow = row * segHeight / depthHeight
                let segX = depthXMid * segWidth / depthWidth
                let segIdx = segRow * segWidth + min(segX, segWidth - 1)
                let isWalkable = walkableIDs.contains(segLabels[segIdx])

                if !isWalkable {
                    obstacleDistance[col] = depthVal
                    break
                }
            }
        }

        // 4. Surface discontinuities — analyze depth gradients within walkable regions only
        var discontinuities = [Discontinuity]()

        for col in 0..<cols {
            let depthXStart = col * depthWidth / cols
            let depthXEnd = (col + 1) * depthWidth / cols
            let depthXMid = (depthXStart + depthXEnd) / 2
            guard depthXMid < depthWidth else { continue }

            // Extract depth profile within walkable pixels only (bottom up)
            var profile = [Float]()
            for row in stride(from: depthHeight - 1, through: 0, by: -1) {
                let depthVal = depthData[row * depthWidth + depthXMid]
                if depthVal > skyDepthThreshold { continue }

                // Check if this pixel is walkable
                let segRow = row * segHeight / depthHeight
                let segX = depthXMid * segWidth / depthWidth
                let segIdx = segRow * segWidth + min(segX, segWidth - 1)

                if walkableIDs.contains(segLabels[segIdx]) {
                    profile.append(depthVal)
                }
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

        // 5. Ground plane ratio — full image, exclude sky
        var nonSkyPixels = 0
        var walkablePixels = 0

        for row in 0..<segHeight {
            for x in 0..<segWidth {
                // Map seg pixel to depth to check for sky
                let depthRow = row * depthHeight / segHeight
                let depthX = x * depthWidth / segWidth
                if depthRow < depthHeight && depthX < depthWidth {
                    let depthVal = depthData[depthRow * depthWidth + depthX]
                    if depthVal > skyDepthThreshold { continue }
                }

                nonSkyPixels += 1
                if walkableIDs.contains(segLabels[row * segWidth + x]) {
                    walkablePixels += 1
                }
            }
        }

        let groundPlaneRatio = nonSkyPixels > 0 ? Float(walkablePixels) / Float(nonSkyPixels) : 0

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
