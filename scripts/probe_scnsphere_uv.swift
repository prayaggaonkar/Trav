import SceneKit
import Foundation

let sphere = SCNSphere(radius: 1.0)
sphere.segmentCount = 72

guard let verts = sphere.sources(for: .vertex).first,
      let tex = sphere.sources(for: .texcoord).first else {
    print("FAIL"); exit(1)
}

func floats(from source: SCNGeometrySource) -> [Float] {
    var out = [Float](repeating: 0, count: source.vectorCount * source.componentsPerVector)
    let bytes = [UInt8](source.data)
    for i in 0..<source.vectorCount {
        let base = source.dataOffset + i * source.dataStride
        for c in 0..<source.componentsPerVector {
            let o = base + c * 4
            var f: Float = 0
            withUnsafeMutableBytes(of: &f) { dest in
                bytes[o..<o+4].withUnsafeBytes { src in dest.copyMemory(from: src) }
            }
            out[i * source.componentsPerVector + c] = f
        }
    }
    return out
}

let V = floats(from: verts)
let T = floats(from: tex)
let n = verts.vectorCount
print("n=\(n)")

func nearestUV(dx: Double, dy: Double, dz: Double) -> (Double, Double) {
    var best = 1e9, bu = 0.0, bv = 0.0
    for i in 0..<n {
        let x = Double(V[i*3]), y = Double(V[i*3+1]), z = Double(V[i*3+2])
        let d = (x-dx)*(x-dx)+(y-dy)*(y-dy)+(z-dz)*(z-dz)
        if d < best { best = d; bu = Double(T[i*2]); bv = Double(T[i*2+1]) }
    }
    return (bu, bv)
}

func expected(lat: Double, lon: Double) -> (Double, Double) {
    ((lon + 180) / 360, (90 - lat) / 180)
}

func score(_ got: (Double, Double), _ exp: (Double, Double)) -> Double {
    var du = abs(got.0 - exp.0)
    du = min(du, 1 - du)
    return du + abs(got.1 - exp.1)
}

let cities = [("SF",37.7749,-122.4194),("Paris",48.8566,2.3522),("Tokyo",35.6762,139.6503),("NYC",40.7128,-74.0060)]

typealias F = (Double,Double)->(Double,Double,Double)
let formulas: [(String, F)] = [
    ("A_sin_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), c*cos(o)) }),
    ("B_neg_both", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), -c*cos(o)) }),
    ("C_old_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), c*sin(o)) }),
    ("D_threejs", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), -c*sin(o)) }),
    ("E_negx", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), c*cos(o)) }),
    ("F_negz", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), -c*cos(o)) }),
    ("G_lonm90", { la, lo in let a=la*(.pi/180), o=(lo-90)*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), c*sin(o)) }),
    ("H_lonp90", { la, lo in let a=la*(.pi/180), o=(lo+90)*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), c*sin(o)) }),
]

var lines: [String] = []
for (fname, f) in formulas {
    var total = 0.0
    var detail = ""
    for (name, lat, lon) in cities {
        let d = f(lat, lon)
        let got = nearestUV(dx: d.0, dy: d.1, dz: d.2)
        let exp = expected(lat: lat, lon: lon)
        let s = score(got, exp)
        total += s
        detail += String(format: " %@:(%.3f/%.3f vs %.3f/%.3f Δ=%.3f)", name, got.0, got.1, exp.0, exp.1, s)
    }
    let line = String(format: "%-12s totalΔ=%.4f%@", fname, total, detail)
    print(line)
    lines.append(line)
}

print("--- axes ---")
for (label, p) in [("+X", (1.0,0.0,0.0)), ("-X", (-1.0,0.0,0.0)), ("+Z", (0.0,0.0,1.0)), ("-Z", (0.0,0.0,-1.0))] as [(String,(Double,Double,Double))] {
    let uv = nearestUV(dx: p.0, dy: p.1, dz: p.2)
    let line = String(format: "%@ uv=(%.3f,%.3f) => lon≈%.1f", label, uv.0, uv.1, uv.0*360-180)
    print(line)
    lines.append(line)
}

try! lines.joined(separator: "\n").write(toFile: "scripts/probe_result.txt", atomically: true, encoding: .utf8)
