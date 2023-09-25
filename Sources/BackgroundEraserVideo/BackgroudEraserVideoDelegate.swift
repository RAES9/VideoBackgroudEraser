import Foundation

public protocol BackgroudEraserVideoDelegate {
    
    func didFinishToProcesingVideo(url: URL)
    func procesingVideo(percentage: Double)
}
