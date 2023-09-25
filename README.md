[![SPM compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://github.com/apple/swift-package-manager)

## BackgroundEraserVideo

A backgorund eraser video for iOS Using Native Vision/VisionKit (Body) 

## Usage as Framework

### Dependency Injection:
Add protocol to class type and initialize BackgroundEraserVideo.

```swift
class VideoPicker: BackgroudEraserVideoDelegate {
    init() {
        BackgroundEraserVideo.shared().delegate = self
    }
}
```
### Delete background:
Call BackgroundEraserVideo and use deleteBackground fuction.

```swift
BackgroundEraserVideo.deleteBackground(url: urlVideo)
```

### Get new video without background:
After dependency injection you have this method for get video.

```swift
func didFinishToProcesingVideo(url: URL) {
    // Add your code here
}
```

### Get progress:
After dependency injection you have this method for get video, range percentage is 0 to 100.

```swift
func procesingVideo(percentage: Double) {
    // Add your code here
}
```
