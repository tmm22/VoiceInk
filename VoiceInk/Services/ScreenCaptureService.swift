import Foundation
import AppKit
import Vision
import ScreenCaptureKit
import OSLog

@MainActor
class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
