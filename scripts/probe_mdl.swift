import ModelIO
import Foundation
import simd

let allocator = MDLMeshBufferDataAllocator()
let mesh = MDLMesh(sphereWithExtent: SIMD3<Float>(1,1,1),
                   segments: SIMD2<UInt32>(72, 72),
                   inwardNormals: false,
                   geometryType: .triangles,
                   allocator: allocator)

guard let vn = mesh.vertexBuffers.first else { fatalError("no vb") }
// MDLMesh sphere layout: need vertex descriptor
let desc = mesh.vertexDescriptor
print("attrs:")
for i in 0..<desc.attributes.count {
    let a = desc.attributes[i] as! MDLVertexAttribute
    print(" ", a.name, "format", a.format.rawValue, "offset", a.offset, "buffer", a.bufferIndex)
}

// Prefer SceneKit export via MDL then compare — actually use known MDL layout
// Extract positions and texturecoords
func attrNamed(_ name: String) -> MDLVertexAttribute? {
    for i in 0..<desc.attributes.count {
        let a = desc.attributes[i] as! MDLVertexAttribute
        if a.name == name { return a }
    }
    return nil
}

guard let posAttr = attrNamed(MDLVertexAttributePosition),
      let texAttr = attrNamed(MDLVertexAttributeTextureCoordinate) else {
    fatalError("missing attrs")
}

let posBuf = mesh.vertexBuffers[posAttr.bufferIndex]
let texBuf = mesh.vertexBuffers[texAttr.bufferIndex]
let posData = posBuf.map().data as Data
let texData = texBuf.map().data as Data
let posStride = desc.layouts[posAttr.bufferIndex].stride
let texStride = desc.layouts[texAttr.bufferIndex].stride
let count = mesh.vertexCount

func loadFloat3(_ data: Data, offset: Int) -> (Double,Double,Double) {
    var x: Float=0,y: Float=0,z: Float=0
    data.withUnsafeBytes { raw in
        let b = raw.baseAddress! + offset
        x = b.loadUnaligned(as: Float.self)
        y = (b+4).loadUnaligned(as: Float.self)
        z = (b+8).loadUnaligned(as: Float.self)
    }
    return (Double(x),Double(y),Double(z))
}
func loadFloat2(_ data: Data, offset: Int) -> (Double,Double) {
    var u: Float=0,v: Float=0
    data.withUnsafeBytes { raw in
        let b = raw.baseAddress! + offset
        u = b.loadUnaligned(as: Float.self)
        v = (b+4).loadUnaligned(as: Float.self)
    }
    return (Double(u),Double(v))
}

var positions = [(Double,Double,Double)]()
var uvs = [(Double,Double)]()
positions.reserveCapacity(count)
uvs.reserveCapacity(count)
for i in 0..<count {
    positions.append(loadFloat3(posData, offset: i*posStride + posAttr.offset))
    uvs.append(loadFloat2(texData, offset: i*texStride + texAttr.offset))
}
print("vertices", count)

func nearestUV(dx: Double, dy: Double, dz: Double) -> (Double, Double) {
    var best=1e9, bu=0.0, bv=0.0
    for i in 0..<count {
        let (x,y,z)=positions[i]
        let d=(x-dx)*(x-dx)+(y-dy)*(y-dy)+(z-dz)*(z-dz)
        if d<best { best=d; bu=uvs[i].0; bv=uvs[i].1 }
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

let cities = [("SF",37.7749,-122.4194),("Paris",48.8566,2.3522),("Tokyo",35.6762,139.6503),("NYC",40.7128,-74.0060)]
typealias F = (Double,Double)->(Double,Double,Double)
let formulas: [(String, F)] = [
    ("A_sin_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), c*cos(o)) }),
    ("B_neg_both", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), -c*cos(o)) }),
    ("C_old_cos", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), c*sin(o)) }),
    ("D_threejs", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*cos(o), sin(a), -c*sin(o)) }),
    ("E_negx", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (-c*sin(o), sin(a), c*cos(o)) }),
    ("F_negz", { la, lo in let a=la*(.pi/180), o=lo*(.pi/180); let c=cos(a); return (c*sin(o), sin(a), -c*cos(o)) }),
]

var lines=[String]()
for (fname,f) in formulas {
    var total=0.0
    var detail=""
    for (name,lat,lon) in cities {
        let d=f(lat,lon)
        let got=nearestUV(dx:d.0,dy:d.1,dz:d.2)
        let exp=expected(lat:lat,lon:lon)
        let s=score(got,exp)
        total+=s
        detail += String(format:" %@:(%.3f/%.3f vs %.3f/%.3f Δ=%.3f)", name, got.0,got.1,exp.0,exp.1,s)
    }
    lines.append(String(format:"%-12s totalΔ=%.4f%@", fname,total,detail))
}
lines.append("--- axes ---")
for (label,p) in [("+X",(1.0,0.0,0.0)),("-X",(-1.0,0.0,0.0)),("+Z",(0.0,0.0,1.0)),("-Z",(0.0,0.0,-1.0))] as [(String,(Double,Double,Double))] {
    let uv=nearestUV(dx:p.0,dy:p.1,dz:p.2)
    lines.append(String(format:"%@ uv=(%.3f,%.3f)", label, uv.0, uv.1))
}
let out=lines.joined(separator:"\n")
try! out.write(toFile:"scripts/probe_result.txt", atomically:true, encoding:.utf8)
print(out)
