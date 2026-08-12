//
//  QRScannerView.swift
//  RemoteDev
//
//  VisionKit の DataScanner で QR を読み取る (iOS 16+)。PC 側の pair.png を読み取ってペアリング。
//

import SwiftUI
import VisionKit

struct QRScannerView: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: QRScannerView

        init(_ parent: QRScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd allItems: [RecognizedItem]) {
            for item in allItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    dataScanner.dismiss(animated: true)
                    parent.onResult(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                dataScanner.dismiss(animated: true)
                parent.onResult(value)
            }
        }
    }
}
