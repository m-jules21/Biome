# Biome

Biome is an iOS ecosystem simulation game built with SwiftUI and SpriteKit. The Xcode project targets iOS 17 and later.

## Build

Open `Biome.xcodeproj` in Xcode, select the `Biome` scheme, then build for an iOS simulator or device. Signing is required to install on a physical device.

## GitHub Actions

The `iOS Build` workflow builds the app for the iOS Simulator on pushes to `main` or `master`, pull requests, and manual runs. It does not require signing credentials.
