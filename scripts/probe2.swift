import SceneKit
import Foundation

let sphere = SCNSphere(radius: 1.0)
sphere.segmentCount = 72
guard let verts = sphere.sources(for: .vertex).first,
      let tex = sphere.sources(for: .texcoord).first else { fatalError() }

var out = ""
func log(_ s: String) { out += s + "\n"; print(s) }

let vBytes = verts.data
let tBytes = tex.data
func f32(_ data: Data, _ at: Int) -> Float {
    data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: Float.self) }
}

let n = verts.vectorCount
log("n=\(n) stride=\(verts.dataStride) texOff=\(tex.dataOffset)")

// Collect normalized positions + uvs
var P = [(Double,Double,Double)]()
var UV = [(Double,Double)]()
for i in 0..<n {
    let bo = verts.dataOffset + i * verts.dataStride
    var x = Double(f32(vBytes, bo)), y = Double(f32(vBytes, bo+4)), z = Double(f32(vBytes, bo+8))
    let len = (x*x+y*y+z*z).squareRoot()
    if len > 1e-8 { x/=len; y/=len; z/=len }
    let to = tex.dataOffset + i * tex.dataStride
    P.append((x,y,z))
    UV.append((Double(f32(tBytes, to)), Double(f32(tBytes, to+4))))
}

log("--- axes ---")
var seen = Set<String>()
for i in 0..<n {
    let (x,y,z) = P[i]
    if abs(y) > 0.12 { continue }
    let ax = abs(x), az = abs(z)
    var label: String? = nil
    if ax > 0.92 && az < 0.25 { label = x > 0 ? "+X" : "-X" }
    if az > 0.92 && ax < 0.25 { label = z > 0 ? "+Z" : "-Z" }
    guard let label, seen.insert(label).inserted else { continue }
    let (u,v) = UV[i]
    log(String(format: "%@ xyz=(%.3f,%.3f,%.3f) uv=(%.3f,%.3f) lon≈%.1f", label,x,y,z,u,v, u*360-180))
}

func nearestUV(_ dx: Double, _ dy: Double, _ dz: Double) -> (Double, Double) {
    let len = (dx*dx+dy*dy+dz*dz).squareRoot()
    let tx=dx/len, ty=dy/len, tz=dz/len
    var best=1e9, bu=0.0, bv=0.0
    for i in 0..<n {
        let (x,y,z)=P[i]
        let d=(x-tx)*(x-tx)+(y-ty)*(y-ty)+(z-tz)*(z-tz)
        if d<best { best=d; bu=UV[i].0; bv=UV[i].1 }
    }
    return (bu,bv)
}
func expected(lat: Double, lon: Double) -> (Double, Double) {
    ((lon + 180) / 360, (90 - lat) / 180)
}
func score(_ got: (Double, Double), _ exp: (Double, Double)) -> Double {
    var du = abs(got.0 - exp.0); du = min(du, 1-du)
    return du + abs(got.1 - exp.1)
}

let cities = [("SF",37.7749,-122.4194),("Paris",48.8566,2.3522),("Tokyo",35.6762,139.6503),("NYC",40.7128,-74.0060),("Sydney",-33.8688,151.2093)]
typealias F = (Double,Double)->(Double,Double,Double)
let formulas: [(String, F)] = [
    ("A_sin_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), c*cos(o)) }),
    ("B_neg_both", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), -c*cos(o)) }),
    ("C_old_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), c*sin(o)) }),
    ("D_threejs", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), -c*sin(o)) }),
    ("E_negx", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), c*cos(o)) }),
    ("F_negz", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), -c*cos(o)) }),
    ("G_lonm90", { la, lo in let a=la*(.pi/180), o=(lo-90)*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), c*cos(o)) }),
    ("H_nlon_sincos", { la, lo in let a=la*(.pi/180), o=(-lo)*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), c*cos(o)) }),
]

log("--- formulas ---")
for (fname, f) in formulas {
    var total = 0.0
    var detail = ""
    for (name, lat, lon) in cities {
        let d = f(lat, lon)
        let got = nearestUV(d.0, d.1, d.2)
        let exp = expected(lat: lat, lon: lon)
        let s = score(got, exp)
        total += s
        detail += String(format: " %@:Δ=%.3f", name, s)
    }
    log(String(format: "%@ totalΔ=%.4f%@", fname, total, detail))
}

try! out.write(toFile: "scripts/probe_result.txt", atomically: true, encoding: .utf8)
