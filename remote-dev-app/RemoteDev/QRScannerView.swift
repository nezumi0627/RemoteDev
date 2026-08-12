//
//  QRScannerView.swift
//  RemoteDev
//
//  VisionKit の DataScanner で QR を読み取る (iOS 16+)。
//  スキャンは startScanning() を明示しないと始まらないので viewDidAppear で開始する。
//

import SwiftUI
import VisionKit

struct QRScannerView: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            return QRScannerViewController(onResult: onResult, onCancel: onCancel)
        }
        return QRUnavailableViewController(onCancel: onCancel)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Scanner

final class QRScannerViewController: DataScannerViewController, DataScannerViewControllerDelegate {
    private let onResult: (String) -> Void
    private let onCancel: () -> Void

    init(onResult: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onResult = onResult
        self.onCancel = onCancel
        super.init(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isScanning {
            stopScanning()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addCloseButton()
    }

    // MARK: DataScannerViewControllerDelegate

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd allItems: [RecognizedItem]) {
        for item in allItems {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                onResult(value)
                return
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
            onResult(value)
        }
    }

    private func addCloseButton() {
        let button = UIButton(type: .system)
        button.setTitle("閉じる", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black.withAlphaComponent(0.55)
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.onCancel() }, for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
    }
}

// MARK: - Fallback (カメラが使えない場合)

final class QRUnavailableViewController: UIViewController {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "カメラが使用できません。\nPC の IP を「設定 > PC コンパニオン」に直接入力してください。"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.setTitle("閉じる", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.onCancel() }, for: .touchUpInside)

        view.addSubview(label)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
