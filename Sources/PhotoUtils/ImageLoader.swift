import Photos
import Cocoa

typealias PlatformImage = NSImage

final class ImageLoader {
    var imageManager: PHImageManager = PHCachingImageManager()
    var semaphore: Semaphore = .init(capacity: 20)
    
    static let `default`: ImageLoader = .init()
    
    func loadImage(for asset: PHAsset, targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode, resizeMode: PHImageRequestOptionsResizeMode, contentMode: PHImageContentMode) async throws -> PlatformImage {
        guard deliveryMode != .opportunistic else { preconditionFailure() }
        var result: PlatformImage?
        for try await image in loadImage(for: asset, targetSize: targetSize, deliveryMode: deliveryMode, resizeMode: resizeMode, contentMode: contentMode) {
            result = image
        }
        guard let result else { preconditionFailure() }
        return result
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode, resizeMode: PHImageRequestOptionsResizeMode, contentMode: PHImageContentMode) -> AsyncThrowingStream<PlatformImage, Error> {
        .init { continuation in
            Task {
                await semaphore.wait()
                
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                options.deliveryMode = deliveryMode
                options.resizeMode = resizeMode
                options.isNetworkAccessAllowed = true
                if #available(macOS 14, *) {
                    options.allowSecondaryDegradedImage = true
                }
                
                let requestID = imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options, resultHandler: { [semaphore] image, info in
                    guard info?[PHImageCancelledKey] as? Bool != true else { return }
                    if let error = info?[PHImageErrorKey] as! Error? {
                        continuation.finish(throwing: error)
                        Task { await semaphore.signal() }
                        return
                    }
                    guard let image = image else { preconditionFailure("unexpected nil image") }
                    continuation.yield(image)
                    if info?[PHImageResultIsDegradedKey] as? Bool != true {
                        continuation.finish()
                        Task { await semaphore.signal() }
                    }
                })
                continuation.onTermination = { [weak self] termination in
                    if case .cancelled = termination {
                        self?.imageManager.cancelImageRequest(requestID)
                        continuation.finish(throwing: CancellationError()) // suprised this is necessary, but seems to yield nil otherwise
                    }
                }
            }
        }
    }
}

actor Semaphore {
    private var capacity: Int {
        didSet {
            assert(capacity >= 0)
        }
    }
    struct Waiter {
        var priority: TaskPriority
        var continuation: CheckedContinuation<Void, Never>
    }
    private var waiters: [Waiter] = []

    init(capacity: Int = 0) {
        self.capacity = capacity
    }

    func wait() async {
        if capacity > 0 {
            capacity -= 1
        } else {
            let priority = Task.currentPriority
            await withCheckedContinuation { waiters.append(.init(priority: priority, continuation: $0)) }
        }
    }

    func signal() {
        if waiters.isEmpty {
            capacity += 1
        } else {
            // FIXME: prioritize higher priority tasks before lower priority tasks!
            waiters.removeFirst().continuation.resume()
        }
    }
    
    func withCriticalSection<Result>(_ runCriticalSection: () async -> Result) async -> Result {
        await wait()
        defer { signal() }
        return await runCriticalSection()
    }
}
