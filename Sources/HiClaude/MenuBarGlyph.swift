import AppKit

/// Glifo próprio da barra de menu: o balão do hi envolvido pelo arco de
/// renovação, em três estados — contorno (ocioso), preenchido (Janela ativa)
/// e exclamação no balão (problema). Template image: a barra tinge conforme
/// o tema; pausado continua sendo opacidade aplicada pela view.
enum MenuBarGlyph {
    enum State: CaseIterable {
        case idle, active, problem

        /// Mesma prioridade do símbolo antigo: problema > janela ativa > ocioso.
        init(hasProblem: Bool, hasActiveWindow: Bool) {
            if hasProblem { self = .problem }
            else if hasActiveWindow { self = .active }
            else { self = .idle }
        }
    }

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            switch state {
            case .idle: drawCycle(); drawBubble(filled: false)
            case .active: drawCycle(); drawBubble(filled: true)
            case .problem: drawProblemBubble()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Arco de renovação (290° em sentido horário) com seta apontando para a
    /// folga no topo. Coordenadas em y para baixo (imagem flipped).
    private static func drawCycle() {
        let center = NSPoint(x: 9, y: 9)
        let radius: CGFloat = 6.15
        let arc = NSBezierPath()
        // Ângulos no espaço já invertido: crescer o ângulo = horário na tela.
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: -55, endAngle: 235, clockwise: false)
        arc.lineWidth = 1.45
        arc.lineCapStyle = .round
        arc.stroke()

        // Ponta da seta no fim do arco (11h), tangente ao sentido do giro.
        let end = NSPoint(x: center.x + radius * cos(235 * .pi / 180),
                          y: center.y + radius * sin(235 * .pi / 180))
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 1.8, y: 0))
        head.line(to: NSPoint(x: -1.1, y: 1.4))
        head.line(to: NSPoint(x: -1.1, y: -1.4))
        head.close()
        var transform = AffineTransform(translationByX: end.x, byY: end.y)
        transform.rotate(byDegrees: -35)
        head.transform(using: transform)
        head.fill()
    }

    /// Balão pequeno dentro do arco, com rabinho; contorno ou preenchido.
    private static func drawBubble(filled: Bool) {
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 7.1, y: 11.1))
        tail.line(to: NSPoint(x: 6.3, y: 12.9))
        tail.line(to: NSPoint(x: 8.7, y: 11.3))
        tail.close()
        tail.fill()

        if filled {
            NSBezierPath(roundedRect: NSRect(x: 5.55, y: 6.45, width: 6.9, height: 4.8),
                         xRadius: 1.5, yRadius: 1.5).fill()
        } else {
            let outline = NSBezierPath(
                roundedRect: NSRect(x: 6.1, y: 7.0, width: 5.8, height: 3.7),
                xRadius: 1.2, yRadius: 1.2)
            outline.lineWidth = 1.1
            outline.stroke()
        }
    }

    /// Estado de problema: balão grande com exclamação vazada, sem arco —
    /// a ausência do ciclo também sinaliza que a renovação não está girando.
    private static func drawProblemBubble() {
        let bubble = NSBezierPath(
            roundedRect: NSRect(x: 3, y: 3.4, width: 12, height: 9.4),
            xRadius: 2.6, yRadius: 2.6)
        bubble.windingRule = .evenOdd
        bubble.append(NSBezierPath(
            roundedRect: NSRect(x: 8.3, y: 5.0, width: 1.4, height: 3.8),
            xRadius: 0.7, yRadius: 0.7))
        bubble.append(NSBezierPath(
            ovalIn: NSRect(x: 8.2, y: 9.6, width: 1.6, height: 1.6)))
        bubble.fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.3, y: 12.6))
        tail.line(to: NSPoint(x: 4.5, y: 14.9))
        tail.line(to: NSPoint(x: 7.6, y: 12.8))
        tail.close()
        tail.fill()
    }
}
