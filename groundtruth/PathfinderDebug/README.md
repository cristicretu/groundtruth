# Pathfinder Debug Viewer

Mac companion app for visualizing Pathfinder data in FSD-style.

## Usage

```bash
cd PathfinderDebug
swift run
```

Or compile:

```bash
swiftc -o PathfinderDebug DebugApp.swift
./PathfinderDebug
```

## What it shows

- **World View**: Bird's eye view of obstacles (red) and curbs (yellow)
- **Depth Preview**: Grayscale depth image from iPhone LiDAR
- **Stats**: FPS, nearest obstacle, heading, obstacle count

## Connecting

1. Run this app on your Mac
2. Note your Mac's IP address (System Preferences > Network)
3. On iPhone, the app will auto-connect via Bonjour
4. Or manually specify the Mac IP in the iPhone app

The app listens on port 8765 by default.
