import SwiftUI
import Photos

/// The phone's photo library, newest first, for the photos app.
///
/// Nothing is read until the photos app is on the glasses, and then only what is on show: the
/// photo in the widget or the centre, and the gallery's page of thumbnails. Pictures in iCloud
/// are fetched from Apple as Photos itself would.
@MainActor
public final class PhotosProvider {
    private var assets: PHFetchResult<PHAsset>?
    private let manager = PHCachingImageManager()
    /// Small pictures by index, for the gallery; the large one on its own.
    private(set) var thumbnails: [Int: Image] = [:]
    private(set) var large: (index: Int, image: Image)?
    private var loading: Set<String> = []
    /// Something arrived.
    public var onChange: (() -> Void)?

    public init() {}

    public var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    public var count: Int { assets?.count ?? 0 }

    /// Asks once, then reads the list of photos (not the photos).
    public func start() async {
        if assets != nil { return }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        assets = PHAsset.fetchAssets(with: options)
        onChange?()
    }

    /// "12 OCTOBER 2026".
    public func caption(_ index: Int) -> String {
        guard let assets, index >= 0, index < assets.count, let date = assets[index].creationDate else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: date).uppercased()
    }

    /// Every picture loaded so far, the large one over its thumbnail.
    public var images: [Int: Image] {
        var all = thumbnails
        if let large { all[large.index] = large.image }
        return all
    }

    /// Loads what is on show and lets go of the rest: these thumbnails, and one large.
    public func show(thumbnails wanted: [Int], large index: Int?) {
        guard let assets else { return }
        let keep = Set(wanted)
        thumbnails = thumbnails.filter { keep.contains($0.key) }
        for i in wanted where i >= 0 && i < assets.count && thumbnails[i] == nil {
            request(i, size: CGSize(width: 360, height: 360), mode: .aspectFill) { [weak self] image in
                self?.thumbnails[i] = image
            }
        }
        guard let index, index >= 0, index < assets.count else { large = nil; return }
        if large?.index == index { return }
        request(index, size: CGSize(width: 1800, height: 1200), mode: .aspectFit) { [weak self] image in
            self?.large = (index, image)
        }
    }

    private func request(_ index: Int, size: CGSize, mode: PHImageContentMode,
                         done: @escaping @MainActor (Image) -> Void) {
        guard let assets else { return }
        let key = "\(index)-\(Int(size.width))"
        guard !loading.contains(key) else { return }
        loading.insert(key)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        manager.requestImage(for: assets[index], targetSize: size, contentMode: mode, options: options) { picture, _ in
            #if canImport(UIKit)
            let image = picture.map { Image(uiImage: $0) }
            #else
            let image = picture.map { Image(nsImage: $0) }
            #endif
            Task { @MainActor [weak self] in
                self?.loading.remove(key)
                if let image {
                    done(image)
                    self?.onChange?()
                }
            }
        }
    }
}
