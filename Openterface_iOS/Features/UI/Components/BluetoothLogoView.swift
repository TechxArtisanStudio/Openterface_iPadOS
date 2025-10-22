//
//  BluetoothLogoView.swift
//  Openterface_iOS
//
//  Created by AI Assistant on 10/22/25.
//

import SwiftUI
import UIKit

// MARK: - UIKit Bluetooth Logo
class BluetoothLogo: UIView {
    var color: UIColor!
    
    convenience init(withColor color: UIColor, andFrame frame: CGRect) {
        self.init(frame: frame)
        self.backgroundColor = .clear
        self.color = color
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        let h = self.frame.height
        
        // Scale down slightly and offset to move down without clipping
        let scale: CGFloat = 0.9
        let offsetY: CGFloat = h * 0.08
        
        let y1 = h * 0.05 * scale
        let y2 = h * 0.25 * scale
        let height = h * scale
        
        context?.translateBy(x: h * (1 - scale) / 2, y: offsetY)
        
        context?.move(to: CGPoint(x: y2, y: y2))
        context?.addLine(to: CGPoint(x: height - y2, y: height - y2))
        context?.addLine(to: CGPoint(x: height/2, y: height - y1))
        context?.addLine(to: CGPoint(x: height/2, y: y1))
        context?.addLine(to: CGPoint(x: height - y2, y: y2))
        context?.addLine(to: CGPoint(x: y2, y: height - y2))
        
        context?.setStrokeColor(color.cgColor)
        context?.setLineCap(.round)
        context?.setLineWidth(2)
        context?.strokePath()
    }
}

// MARK: - SwiftUI Wrapper
struct BluetoothLogoView: UIViewRepresentable {
    let color: Color
    let size: CGFloat
    
    init(color: Color = .blue, size: CGFloat = 50) {
        self.color = color
        self.size = size
    }
    
    func makeUIView(context: Context) -> BluetoothLogo {
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        let uiColor = UIColor(color)
        return BluetoothLogo(withColor: uiColor, andFrame: frame)
    }
    
    func updateUIView(_ uiView: BluetoothLogo, context: Context) {
        uiView.color = UIColor(color)
        uiView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        uiView.setNeedsDisplay()
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BluetoothLogo, context: Context) -> CGSize {
        return CGSize(width: size, height: size)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        BluetoothLogoView(color: .blue, size: 40)
        BluetoothLogoView(color: .green, size: 40)
        BluetoothLogoView(color: .red, size: 40)
        BluetoothLogoView(color: .gray, size: 40)
    }
    .padding()
}
