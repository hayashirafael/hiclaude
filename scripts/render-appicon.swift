// Gera o master do ícone do app (1024×1024, fundo transparente).
// Fonte canônica do desenho: balão do "hi" envolvido pelo arco de renovação.
// Uso: swift scripts/render-appicon.swift assets/AppIcon.png
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size = 1024
// Coordenadas de desenho em y para cima (origem embaixo à esquerda);
// yCG(_) converte medidas tiradas do rascunho (y para baixo).
func yCG(_ y: CGFloat) -> CGFloat { CGFloat(size) - y }

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("uso: render-appicon.swift <saída.png>\n".utf8))
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size,
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func cor(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let terracotaClaro = cor(0xEE8F66)
let terracotaEscuro = cor(0xBC5335)
let branco = cor(0xFFFFFF)

// Quadrado arredondado de fundo com gradiente diagonal + luz no topo
let quadro = CGRect(x: 64, y: 64, width: 896, height: 896)
let squircle = CGPath(roundedRect: quadro, cornerWidth: 205, cornerHeight: 205, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
ctx.drawLinearGradient(
    CGGradient(colorsSpace: space, colors: [terracotaClaro, terracotaEscuro] as CFArray,
               locations: [0, 1])!,
    start: CGPoint(x: 64, y: yCG(64)), end: CGPoint(x: 960, y: yCG(960)), options: [])
ctx.drawLinearGradient(
    CGGradient(colorsSpace: space,
               colors: [cor(0xFFFFFF, 0.22), cor(0xFFFFFF, 0)] as CFArray,
               locations: [0, 1])!,
    start: CGPoint(x: 512, y: yCG(64)), end: CGPoint(x: 512, y: yCG(557)), options: [])
ctx.restoreGState()

// Arco de renovação: 300° em sentido horário, folga no topo para a seta
let centroArco = CGPoint(x: 512, y: yCG(505))
ctx.setStrokeColor(cor(0xFFFFFF, 0.92))
ctx.setLineWidth(48)
ctx.setLineCap(.round)
ctx.addArc(center: centroArco, radius: 330,
           startAngle: .pi / 3, endAngle: 2 * .pi / 3, clockwise: true)
ctx.strokePath()

// Ponta da seta no fim do arco (11h), apontando para a folga
ctx.saveGState()
ctx.translateBy(x: 347, y: yCG(219))
ctx.rotate(by: .pi / 6)
ctx.setFillColor(cor(0xFFFFFF, 0.92))
ctx.move(to: CGPoint(x: 70, y: 0))
ctx.addLine(to: CGPoint(x: -40, y: 52))
ctx.addLine(to: CGPoint(x: -40, y: -52))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// Balão do hi com rabinho
ctx.setFillColor(branco)
ctx.addPath(CGPath(roundedRect: CGRect(x: 332, y: yCG(643), width: 360, height: 266),
                   cornerWidth: 92, cornerHeight: 92, transform: nil))
ctx.fillPath()
ctx.move(to: CGPoint(x: 420, y: yCG(625)))
ctx.addLine(to: CGPoint(x: 372, y: yCG(711)))
ctx.addLine(to: CGPoint(x: 500, y: yCG(637)))
ctx.closePath()
ctx.fillPath()

// "hi" desenhado como traços (independe de fonte instalada)
ctx.setStrokeColor(terracotaEscuro)
ctx.setLineWidth(56)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 428, y: yCG(430)))            // haste do h
ctx.addLine(to: CGPoint(x: 428, y: yCG(590)))
ctx.strokePath()
ctx.move(to: CGPoint(x: 428, y: yCG(522)))            // arco do h
ctx.addArc(center: CGPoint(x: 478, y: yCG(522)), radius: 50,
           startAngle: .pi, endAngle: 0, clockwise: true)
ctx.addLine(to: CGPoint(x: 528, y: yCG(590)))
ctx.strokePath()
ctx.move(to: CGPoint(x: 596, y: yCG(507)))            // haste do i
ctx.addLine(to: CGPoint(x: 596, y: yCG(590)))
ctx.strokePath()
ctx.setFillColor(terracotaEscuro)                     // pingo do i
ctx.fillEllipse(in: CGRect(x: 596 - 30, y: yCG(447) - 30, width: 60, height: 60))

let imagem = ctx.makeImage()!
let destino = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destino, imagem, nil)
guard CGImageDestinationFinalize(destino) else {
    FileHandle.standardError.write(Data("falha ao gravar \(outURL.path)\n".utf8))
    exit(1)
}
print("gerado: \(outURL.path)")
