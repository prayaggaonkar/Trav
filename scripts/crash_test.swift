print("start")
import SceneKit
print("imported")
let s = SCNSphere(radius: 1)
print("sphere", s.segmentCount)
print("sources", s.sources.count)
for src in s.sources { print(src.semantic.rawValue, src.vectorCount) }
print("done")
