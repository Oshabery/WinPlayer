import CoreGraphics
import Foundation

/// リモート画面のピクセルを保持するスレッドセーフなバッファ（BGRA32）。
/// 接続スレッドが書き込み、メインスレッドが CGImage として読み出す。
final class Framebuffer {
    private let lock = NSLock()
    private var pixels: UnsafeMutableRawPointer?
    private var context: CGContext?
    private(set) var width = 0
    private(set) var height = 0
    private var bytesPerRow: Int { width * 4 }
    private var dirty = false

    deinit {
        pixels?.deallocate()
    }

    /// サイズを変更する（内容は黒でクリアされる）
    func resize(width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard width > 0, height > 0, width != self.width || height != self.height else { return }

        pixels?.deallocate()
        let bpr = width * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bpr * height, alignment: 16)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bpr * height)
        pixels = buffer
        self.width = width
        self.height = height
        // FreeRDP の PIXEL_FORMAT_BGRA32 はメモリ上 B,G,R,A の順 = 32bit リトルエンディアンの ARGB
        context = CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.noneSkipFirst.rawValue)
        dirty = true
    }

    /// FreeRDP のフレームバッファから更新範囲をコピーする（接続スレッドから呼ばれる）
    func update(from source: UnsafePointer<UInt8>, sourceStride: Int,
                sourceWidth: Int, sourceHeight: Int,
                x: Int, y: Int, w: Int, h: Int) {
        if sourceWidth != width || sourceHeight != height {
            resize(width: sourceWidth, height: sourceHeight)
        }

        lock.lock()
        defer { lock.unlock() }
        guard let pixels else { return }

        // 範囲をバッファ内に収める
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }

        let rowBytes = (x1 - x0) * 4
        for row in y0..<y1 {
            let src = source + row * sourceStride + x0 * 4
            let dst = pixels + row * bytesPerRow + x0 * 4
            dst.copyMemory(from: src, byteCount: rowBytes)
        }
        dirty = true
    }

    /// 前回から更新があれば最新の画像を返す（メインスレッドから呼ぶ）
    func takeImageIfDirty() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard dirty, let context else { return nil }
        dirty = false
        return context.makeImage()
    }
}
