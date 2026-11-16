// Inkrail's original lamp models. Development-only SceneKit renderer; the app
// bundles transparent rasterizations and never starts a 3D render loop.
import AppKit
import SceneKit
import Metal
import simd

private typealias V = SIMD3<Float>
private func v(_ p: V) -> SCNVector3 { SCNVector3(p.x, p.y, p.z) }
private func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
private func hash(_ x: Int, _ y: Int) -> Double {
    var n = UInt64(bitPattern: Int64(x + y * 4099)) &* 0x9E3779B185EBCA87
    n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
    n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
    return Double((n ^ (n >> 31)) & 0xFFFF) / 65535
}
private func image(width: Int, height: Int, pixel: (Int, Int) -> (Double, Double, Double)) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    for y in 0..<height { for x in 0..<width {
        let c = pixel(x, y), p = rep.bitmapData! + y * rep.bytesPerRow + x * 4
        p[0] = UInt8(min(255,max(0,c.0 * 255))); p[1] = UInt8(min(255,max(0,c.1 * 255)))
        p[2] = UInt8(min(255,max(0,c.2 * 255))); p[3] = 255
    }}
    let result = NSImage(size: NSSize(width: width, height: height)); result.addRepresentation(rep)
    return result
}
private func material(_ color: NSColor, metal: Double, roughness: Double, fabric: Bool = false) -> SCNMaterial {
    let m = SCNMaterial(); m.lightingModel = .physicallyBased
    m.diffuse.contents = color; m.metalness.contents = metal
    m.roughness.contents = image(width: 512, height: 512) { x, y in
        let n = hash(x, y)
        let r = roughness + (n - 0.5) * 0.075
        return (r,r,r)
    }
    m.normal.contents = image(width: 512, height: 512) { x,y in
        let a = hash(x, y), b = hash(x + 1,y), c = hash(x,y + 1)
        if fabric {
            let warp = sin(Double(x) * .pi / 2) * 0.13, weft = sin(Double(y) * .pi / 3) * 0.09
            return (0.5 + warp + (a - b) * 0.025, 0.5 + weft + (a-c) * 0.025, 1)
        }
        return (0.5 + (a-b)*0.07, 0.5 + (a-c)*0.025, 1)
    }
    m.normal.intensity = fabric ? 0.4 : 0.35
    m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
    m.normal.wrapS = .repeat; m.normal.wrapT = .repeat
    m.isDoubleSided = true
    return m
}
private func mesh(vertices: [SCNVector3], normals: [SCNVector3], uv: [CGPoint], indices: [Int32], material: SCNMaterial) -> SCNNode {
    let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                 SCNGeometrySource(textureCoordinates: uv)],
                        elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    g.materials = [material]
    return SCNNode(geometry:g)
}
private func lathe(_ profile: [(Double, Double)], material: SCNMaterial, segments: Int = 128) -> SCNNode {
    var vertices = [SCNVector3](), normals = [SCNVector3](), uv = [CGPoint](), indices = [Int32]()
    for (j,p) in profile.enumerated() {
        let before = profile[max(0,j-1)], after = profile[min(profile.count-1,j+1)]
        let dr = Float(after.0-before.0), dy = Float(after.1-before.1)
        for i in 0...segments {
            let a = Float(i) / Float(segments) * .pi * 2
            vertices.append(SCNVector3(Float(p.0)*cos(a),Float(p.1),Float(p.0)*sin(a)))
            let n = simd_normalize(V(dy*cos(a),-dr,dy*sin(a)))
            normals.append(v(n)); uv.append(CGPoint(x:Double(i)/Double(segments),y:Double(j)/Double(profile.count-1)))
            if i < segments && j < profile.count-1 {
                let q=Int32(j*(segments+1)+i), d=Int32(segments+1)
                indices += [q,q+d,q+1,q+1,q+d,q+d+1]
            }
        }
    }
    return mesh(vertices:vertices,normals:normals,uv:uv,indices:indices,material:material)
}
private func cylinder(radius: CGFloat, height: CGFloat, position: V, material: SCNMaterial, parent: SCNNode) -> SCNNode {
    let shape=SCNCylinder(radius:radius,height:height); shape.radialSegmentCount=80; shape.firstMaterial=material
    let n=SCNNode(geometry:shape);n.position=v(position);parent.addChildNode(n);return n
}
private func tube(_ points: [V], radius: Float, material: SCNMaterial) -> SCNNode {
    let segments=32
    var vertices=[SCNVector3](), normals=[SCNVector3](),uv=[CGPoint](),indices=[Int32]()
    for j in points.indices {
        let tangent=simd_normalize(points[min(points.count-1,j+1)]-points[max(0,j-1)])
        let normal=simd_normalize(simd_cross(tangent,V(0,0,1)))
        for i in 0...segments {
            let a=Float(i)/Float(segments) * .pi * 2
            let n=normal*cos(a)+V(0,0,1)*sin(a)
            vertices.append(v(points[j]+n*radius));normals.append(v(n))
            uv.append(CGPoint(x:Double(i)/Double(segments),y:Double(j)/Double(points.count-1)))
            if i<segments && j<points.count-1 {
                let q=Int32(j*(segments+1)+i),d=Int32(segments+1)
                indices += [q,q+d,q+1,q+1,q+d,q+d+1]
            }
        }
    }
    return mesh(vertices:vertices,normals:normals,uv:uv,indices:indices,material:material)
}
private func shell(radius: Float, length: Float, material: SCNMaterial, inward: Bool = false) -> SCNNode {
    let rings=64, slices=80
    var vertices=[SCNVector3](),normals=[SCNVector3](),uv=[CGPoint](),indices=[Int32]()
    for j in 0...rings { for i in 0...slices {
        // Rolled brass shell; the bottom opening is tilted toward the paper.
        let a=Float(i)/Float(slices) * .pi
        let x=(Float(j)/Float(rings)-0.5)*length
        let edgeRoll = 1 - 0.045 * pow(abs(2*x/length), 12)
        vertices.append(SCNVector3(x,radius*sin(a)*edgeRoll,radius*cos(a)*edgeRoll))
        normals.append(v(V(0,sin(a),cos(a)) * (inward ? -1:1)))
        uv.append(CGPoint(x:Double(j)/Double(rings),y:Double(i)/Double(slices)))
        if i<slices && j<rings {
            let q=Int32(j*(slices+1)+i),d=Int32(slices+1)
            indices += [q,q+d,q+1,q+1,q+d,q+d+1]
        }
    }}
    return mesh(vertices:vertices,normals:normals,uv:uv,indices:indices,material:material)
}
private func endCap(radius: Float, material: SCNMaterial, left: Bool) -> SCNNode {
    let normal = SCNVector3(left ? -1:1,0,0)
    var vertices=[SCNVector3(0,0,0)],normals=[normal],uv=[CGPoint(x:0.5,y:0.5)],indices=[Int32]()
    for i in 0...80 {
        let a=Float(i)/80 * .pi
        vertices.append(SCNVector3(0,radius*sin(a),radius*cos(a)))
        normals.append(normal);uv.append(CGPoint(x:Double(cos(a))/2+0.5,y:Double(sin(a))))
        if i>0 {indices += left ? [0,Int32(i),Int32(i+1)] : [0,Int32(i+1),Int32(i)]}
    }
    return mesh(vertices:vertices,normals:normals,uv:uv,indices:indices,material:material)
}
private struct Lamp {
    let body: SCNNode
    let emitter: SCNNode
    let foot: V
    let emission: V
}
private func makeLamp(linen: Bool) -> Lamp {
    let bronze = material(rgb(0.32,0.205,0.092),metal:0.9,roughness:0.29)
    let polished = material(rgb(0.51,0.32,0.13),metal:0.95,roughness:0.22)
    let dark = material(rgb(0.105,0.073,0.040),metal:0.78,roughness:0.34)
    let inner = material(rgb(0.61,0.53,0.36),metal:0.65,roughness:0.35)
    let body=SCNNode(), emitter=SCNNode()
    let white=SCNMaterial();white.lightingModel = .constant;white.diffuse.contents=NSColor.white;white.isDoubleSided=true
    let footX: Float = -0.39
    let base=lathe([(0,0.025),(0.35,0.025),(0.415,0.035),(0.44,0.055),(0.442,0.085),
                    (0.438,0.13),(0.425,0.15),(0.39,0.16),(0.38,0.177),(0.32,0.185),
                    (0.26,0.20),(0.18,0.218),(0.08,0.23),(0,0.23)],material:bronze)
    base.position.x=CGFloat(footX);body.addChildNode(base)
    let rim=lathe([(0.424,0.135),(0.43,0.14),(0.43,0.15),(0.424,0.156)],material:polished)
    rim.position.x=CGFloat(footX);body.addChildNode(rim)
    let stemX=footX-0.13
    _=cylinder(radius:0.035,height:1.72,position:V(stemX,1.08,0),material:bronze,parent:body)
    for (y,r,h) in [(0.25,0.085,0.045),(0.30,0.063,0.07),(0.37,0.049,0.025),
                     (1.17,0.056,0.055),(1.24,0.06,0.035),(1.29,0.046,0.02)] {
        let ring=lathe([(0,y-h/2),(r*0.85,y-h/2),(r,y-h/2+0.01),(r,y+h/2-0.01),(r*0.85,y+h/2),(0,y+h/2)],material:polished)
        ring.position.x=CGFloat(stemX);body.addChildNode(ring)
    }
    _=cylinder(radius:0.027,height:0.045,position:V(footX+0.12,0.24,0.16),material:polished,parent:body)
    let button=SCNSphere(radius:0.03);button.firstMaterial=polished
    let bn=SCNNode(geometry:button);bn.position=v(V(footX+0.12,0.265,0.16));bn.scale=SCNVector3(1,0.45,1);body.addChildNode(bn)
    if linen {
        let fabric=material(rgb(0.37,0.33,0.25),metal:0,roughness:0.9,fabric:true)
        let sh=lathe([(0.52,1.83),(0.515,1.845),(0.27,2.48),(0.263,2.485),
                      (0.25,2.475),(0.50,1.845),(0.52,1.83)],material:fabric)
        sh.position.x=CGFloat(footX+0.13);sh.name="translucent-linen";body.addChildNode(sh)
        for (radius,y) in [(0.515,1.84),(0.265,2.48)] {
            let ring=lathe([(radius-0.008,y-0.007),(radius+0.008,y-0.004),(radius+0.008,y+0.004),(radius-0.008,y+0.007)],material:fabric)
            ring.position.x=CGFloat(footX+0.13);body.addChildNode(ring)
        }
        let disk=SCNCylinder(radius:0.47,height:0.006);disk.firstMaterial=white
        let en=SCNNode(geometry:disk);en.position=v(V(footX+0.13,1.85,0));emitter.addChildNode(en)
        let rimGlow=lathe([(0.515,1.824),(0.527,1.83),(0.515,1.839)],material:white)
        rimGlow.position.x=CGFloat(footX+0.13);emitter.addChildNode(rimGlow)
        return Lamp(body:body,emitter:emitter,foot:V(footX,0.06,0),emission:V(footX+0.13,1.83,0.25))
    }
    var bent=[V(stemX,1.88,0),V(stemX,2.02,0)]
    for i in 0...36 {
        let a=Float(i)/36 * .pi/2
        bent.append(V(stemX+0.25*(1-cos(a)),2.02+0.25*sin(a),0))
    }
    bent.append(V(-0.10,2.27,0)); body.addChildNode(tube(bent,radius:0.033,material:polished))
    let center=V(0.45,2.27,0)
    let shade=SCNNode();shade.position=v(center);shade.eulerAngles.x = -0.10
    let outer=shell(radius:0.28,length:1.12,material:dark);shade.addChildNode(outer)
    let lining=shell(radius:0.268,length:1.106,material:inner,inward:true);shade.addChildNode(lining)
    for x: Float in [-0.56,0.56] {
        let cap=endCap(radius:0.275,material:material(rgb(0.075,0.051,0.029),metal:0.65,roughness:0.44),left:x < 0);cap.position.x=CGFloat(x);shade.addChildNode(cap)
        var edge=[V]()
        for i in 0...80 {let a=Float(i)/80 * .pi;edge.append(V(x,0.278*sin(a),0.278*cos(a)))}
        shade.addChildNode(tube(edge,radius:0.006,material:polished))
    }
    // Rolled lower edges are real geometry, producing narrow warm-metal reflections.
    for z: Float in [-0.273,0.273] {shade.addChildNode(tube([V(-0.55,0,z),V(0.55,0,z)],radius:0.008,material:polished))}
    body.addChildNode(shade)
    let pivot=cylinder(radius:0.071,height:0.09,position:V(-0.16,2.27,0),material:bronze,parent:body)
    pivot.eulerAngles.z = .pi/2
    let pivotScrew=cylinder(radius:0.045,height:0.025,position:V(-0.22,2.27,0),material:polished,parent:body)
    pivotScrew.eulerAngles.z = .pi/2
    let light=SCNBox(width:1.025,height:0.006,length:0.49,chamferRadius:0.015);light.firstMaterial=white
    let en=SCNNode(geometry:light);en.position=v(center + V(0,-0.007,0));en.eulerAngles.x = -0.10;emitter.addChildNode(en)
    let slit=tube([V(-0.52,-0.012,0.279),V(0.52,-0.012,0.279)],radius:0.007,material:white)
    slit.position=v(center);slit.eulerAngles.x = -0.10;emitter.addChildNode(slit)
    return Lamp(body:body,emitter:emitter,foot:V(footX,0.06,0),emission:center+V(0,-0.015,0.27))
}

@main struct Renderer {
    static func main() throws {
        guard CommandLine.arguments.count==2 else {fatalError("Pass output resource directory")}
        guard let gpu=MTLCreateSystemDefaultDevice() else {fatalError("Native Metal GPU unavailable. Run the local generator with GPU access.")}
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let env=image(width:1024,height:512) { x,y in
            let u=Double(x)/1024,v=Double(y)/512
            let window=exp(-pow((u-0.2)/0.045,8)-pow((v-0.30)/0.18,8))*0.80
            let strip=exp(-pow((u-0.68)/0.018,4)-pow((v-0.4)/0.22,4))*0.5
            let ambient=0.10 + 0.10 * max(0,1-v)
            let c=ambient+window+strip
            return (c,c*0.97,c*0.91)
        }
        for linen in [false,true] {
            let lamp=makeLamp(linen:linen),scene=SCNScene()
            scene.background.contents=NSColor.clear
            scene.lightingEnvironment.contents=env;scene.lightingEnvironment.intensity=1.1
            scene.rootNode.addChildNode(lamp.body);scene.rootNode.addChildNode(lamp.emitter)
            let camera=SCNNode();camera.camera=SCNCamera()
            camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=1.8
            camera.camera!.wantsHDR=true;camera.camera!.wantsExposureAdaptation=false
            camera.camera!.bloomIntensity=0;camera.camera!.exposureOffset=0
            let target=SCNNode();target.position=SCNVector3(0.06,1.28,0);scene.rootNode.addChildNode(target)
            camera.position=SCNVector3(-1.5,3.2,8)
            let look=SCNLookAtConstraint(target:target);look.isGimbalLockEnabled=true;camera.constraints=[look]
            scene.rootNode.addChildNode(camera)
            let key=SCNNode();key.light=SCNLight();key.light!.type = .omni;key.light!.intensity=400
            key.light!.color=NSColor.white;key.position=SCNVector3(-3,5,4);scene.rootNode.addChildNode(key)
            let rim=SCNNode();rim.light=SCNLight();rim.light!.type = .omni;rim.light!.intensity=170
            rim.light!.color=NSColor.white;rim.position=SCNVector3(3,2,-3);scene.rootNode.addChildNode(rim)
            let renderer=SCNRenderer(device:gpu,options:nil);renderer.scene=scene;renderer.pointOfView=camera
            let name=linen ? "linen":"brass"
            for emission in [false,true] {
                lamp.body.isHidden=false;lamp.emitter.isHidden = !emission
                if emission {
                    // The shell/base remain in the depth buffer, so only an
                    // actually visible slit contributes to the emitter mask.
                    let black=SCNMaterial();black.lightingModel = .constant
                    black.diffuse.contents=NSColor.black;black.isDoubleSided=true
                    lamp.body.enumerateChildNodes { node,_ in
                        if let g=node.geometry {
                            if node.name == "translucent-linen" {
                                let transmission=SCNMaterial();transmission.lightingModel = .constant
                                transmission.diffuse.contents=NSColor(white:0.18,alpha:1);transmission.isDoubleSided=true
                                g.materials=g.materials.map { _ in transmission }
                            } else {g.materials=g.materials.map { _ in black }}
                        }
                    }
                }
                let rendered=renderer.snapshot(atTime:0,with:CGSize(width:480,height:810),antialiasingMode:.multisampling4X)
                guard let tiff=rendered.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else {fatalError("Native snapshot failed")}
                let destination=output.appendingPathComponent("desk-lamp-\(name)-\(emission ? "emitter":"body").png")
                if emission {
                    let input=rep.cgImage!,w=input.width,h=input.height
                    var pixels=[UInt8](repeating:0,count:w*h*4)
                    pixels.withUnsafeMutableBytes { data in
                        let context=CGContext(data:data.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                                              space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.draw(input,in:CGRect(x:0,y:0,width:w,height:h))
                    }
                    for pixel in 0..<w*h {
                        let i=pixel*4,a=max(pixels[i],pixels[i+1],pixels[i+2])
                        pixels[i]=a;pixels[i+1]=a;pixels[i+2]=a;pixels[i+3]=a
                    }
                    try pixels.withUnsafeMutableBytes { data in
                        let context=CGContext(data:data.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                                              space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                        let mask=NSBitmapImageRep(cgImage:context.makeImage()!)
                        try mask.representation(using:.png,properties:[:])!.write(to:destination)
                    }
                } else {try png.write(to:destination)}
            }
            let foot=renderer.projectPoint(v(lamp.foot)),emitter=renderer.projectPoint(v(lamp.emission))
            print("\(name) body160×270: foot=(\(foot.x/3),\(270-foot.y/3)), emitter=(\(emitter.x/3),\(270-emitter.y/3))")
        }
        print("Rendered four original native PBR lamp assets; no downloaded materials or models.")
    }
}
