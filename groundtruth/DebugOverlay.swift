// DebugOverlay.swift
// On-screen debug HUD for the camera-only navigation pipeline
import SwiftUI

struct DebugOverlayView: View {
    @ObservedObject var engine: NavigationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // FPS
            Text("FPS: \(engine.fps)")

            // Vision pipeline time
            Text(String(format: "Vision: %.1fms", engine.visionTimeMs))

            Divider().overlay(Color.gray.opacity(0.4))

            // Suggested heading arrow
            HStack(spacing: 4) {
                Text("Heading:")
                Image(systemName: "arrow.up")
                    .rotationEffect(.radians(Double(engine.navigationOutput.suggestedHeading)))
                Text(String(format: "%.0f°", engine.navigationOutput.suggestedHeading * 180 / .pi))
            }

            // Nearest obstacle
            let dist = engine.navigationOutput.nearestObstacleDistance
            Text(String(format: "Obstacle: %@", dist < 100 ? String(format: "%.2fm", dist) : "none"))

            // Ground confidence bar
            HStack(spacing: 4) {
                Text("Ground:")
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                        Rectangle()
                            .fill(confidenceColor)
                            .frame(width: geo.size.width * CGFloat(engine.navigationOutput.groundConfidence))
                    }
                    .cornerRadius(2)
                }
                .frame(width: 80, height: 10)
                Text(String(format: "%d%%", Int(engine.navigationOutput.groundConfidence * 100)))
            }

            // Discontinuity warning
            if let disc = engine.navigationOutput.discontinuityAhead, disc.distance < 5 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(disc.magnitude > 0.2 ? .red : .yellow)
                    Text(String(format: "Surface change %.1fm ahead", disc.distance))
                }
            }

            Divider().overlay(Color.gray.opacity(0.4))

            // Navigation state
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateText)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var stateText: String {
        let nav = engine.navigationOutput
        if nav.isPathBlocked { return "BLOCKED" }
        if nav.groundConfidence < 0.3 { return "LOW GROUND CONFIDENCE" }
        if nav.nearestObstacleDistance < 2.0 { return "OBSTACLE" }
        return "CLEAR"
    }

    private var stateColor: Color {
        let nav = engine.navigationOutput
        if nav.isPathBlocked { return .red }
        if nav.groundConfidence < 0.3 { return .orange }
        if nav.nearestObstacleDistance < 2.0 { return .yellow }
        return .green
    }

    private var confidenceColor: Color {
        let c = engine.navigationOutput.groundConfidence
        if c < 0.3 { return .red }
        if c < 0.6 { return .yellow }
        return .green
    }
}
