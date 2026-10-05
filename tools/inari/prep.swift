// tools/inari/prep.swift — derives Inari's light map from its two drawings.
//
// usage (from the repo root):
//   swiftc -O tools/inari/prep.swift -o /tmp/inari_prep && /tmp/inari_prep UzumeEngine/Sources/Presets/Shaders/Inari
//
// From the artist's moonlit-only and fully-lit drawings: the light each pixel receives (lit − unlit,
// luminance), which light source it belongs to (geodesic growth through lit pixels from each glowing
// core), and its rank in that light's falloff (0 faintest … 1 hottest). Writes inari_lights.png
// (r = rank, g = owner id) and inari_lights.json.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
func load(_ p: String) -> ([Float], Int, Int) {
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!; let i = CGImageSourceCreateImageAtIndex(s, 0, nil)!
    let w = i.width, h = i.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.draw(i, in: CGRect(x: 0, y: 0, width: w, height: h))
    func lin(_ v: UInt8) -> Float { let s = Float(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
    var l = [Float](repeating: 0, count: w * h)
    for k in 0..<(w*h) { l[k] = 0.2126 * lin(px[k*4]) + 0.7152 * lin(px[k*4+1]) + 0.0722 * lin(px[k*4+2]) }
    return (l, w, h)
}
let dir = CommandLine.arguments[1]
let (U, W, H) = load(dir + "/inari_unlit.webp"); let (Lt, _, _) = load(dir + "/inari_lit.webp")
var D = [Float](repeating: 0, count: W * H)
for k in 0..<(W*H) { D[k] = max(Lt[k] - U[k], 0) }
// blur (box 9×9, separable) — the drawn texture differs between the two drawings; the light doesn't
func blur(_ a: [Float], _ r: Int) -> [Float] {
    var t = a, o = a
    for y in 0..<H { var s: Float = 0; for x in -r...r { s += a[y*W + max(0, min(W-1, x))] }
        for x in 0..<W { t[y*W+x] = s / Float(2*r+1); s += a[y*W + min(W-1, x+r+1)] - a[y*W + max(0, x-r)] } }
    for x in 0..<W { var s: Float = 0; for y in -r...r { s += t[max(0, min(H-1, y))*W + x] }
        for y in 0..<H { o[y*W+x] = s / Float(2*r+1); s += t[min(H-1, y+r+1)*W + x] - t[max(0, y-r)*W + x] } }
    return o
}
let Ds = blur(D, 4)
let eps: Float = 0.004
// glowing cores: connected regions of strong light
var core = [Int](repeating: 0, count: W * H); var cores: [(Float, Float, Int, Float)] = []   // cx, cy, n, peak
var id = 0
for y0 in 0..<H { for x0 in 0..<W where Ds[y0*W+x0] > 0.05 && core[y0*W+x0] == 0 {
    id += 1; var st = [(x0, y0)]; core[y0*W+x0] = id; var n = 0, sx = 0, sy = 0; var pk: Float = 0
    while let (x, y) = st.popLast() { n += 1; sx += x; sy += y; pk = max(pk, Ds[y*W+x])
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] { let nx = x+dx, ny = y+dy
            if nx >= 0 && ny >= 0 && nx < W && ny < H && Ds[ny*W+nx] > 0.05 && core[ny*W+nx] == 0 { core[ny*W+nx] = id; st.append((nx, ny)) } } }
    cores.append((Float(sx)/Float(n), Float(sy)/Float(n), n, pk))
} }
// Only emitters seed a light: hot cores (lit paper, eyes) and the pagoda's windows. Lit stone is not a
// source — it belongs to whichever emitter's light reaches it. Nearby cores merge (one lamp's panes).
var seedOf = [Int](repeating: 0, count: cores.count + 1)
var seeds: [(Float, Float, Int, Float)] = []
for (i, c) in cores.enumerated() {
    let emitter = c.3 > 0.28 || (c.1 < 300 && c.0 > 1200 && c.3 > 0.12)
    guard emitter else { continue }
    if let j = seeds.firstIndex(where: { hypot($0.0 - c.0, $0.1 - c.1) < 26 }) {
        let s = seeds[j]; let n = s.2 + c.2
        seeds[j] = ((s.0 * Float(s.2) + c.0 * Float(c.2)) / Float(n), (s.1 * Float(s.2) + c.1 * Float(c.2)) / Float(n), n, max(s.3, c.3))
        seedOf[i + 1] = j + 1
    } else { seeds.append(c); seedOf[i + 1] = seeds.count }
}
for k in 0..<(W*H) { core[k] = seedOf[core[k]] }
cores = seeds
// geodesic growth from all emitters at once through pixels that carry light
var owner = core; var q = [Int](); for k in 0..<(W*H) where owner[k] > 0 { q.append(k) }
var head = 0
while head < q.count { let k = q[head]; head += 1; let x = k % W, y = k / W
    for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] { let nx = x+dx, ny = y+dy
        if nx >= 0 && ny >= 0 && nx < W && ny < H { let j = ny*W+nx; if owner[j] == 0 && Ds[j] > eps { owner[j] = owner[k]; q.append(j) } } } }
// rank within the light's own falloff: log scale between eps and that light's peak
var out = [UInt8](repeating: 255, count: W * H * 4)
for k in 0..<(W*H) {
    let o = owner[k]
    var r: Float = 0
    if o > 0 { let pk = cores[o-1].3; r = max(0, min(1, log2(Ds[k] / eps) / log2(pk / eps))) }
    out[k*4] = UInt8(r * 255); out[k*4+1] = UInt8(min(o, 255)); out[k*4+2] = 0
}
let c = CGContext(data: &out, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/inari_lights.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
var js = "[\n"
for (i, cr) in cores.enumerated() { js += String(format: "  {\"id\": %d, \"x\": %.1f, \"y\": %.1f, \"n\": %d, \"peak\": %.3f}%@\n", i+1, cr.0, cr.1, cr.2, cr.3, i == cores.count-1 ? "" : ",") }
try! (js + "]\n").write(toFile: dir + "/inari_lights.json", atomically: true, encoding: .utf8)
print("cores:", cores.count, "owned px:", owner.filter { $0 > 0 }.count, "of", W*H)
