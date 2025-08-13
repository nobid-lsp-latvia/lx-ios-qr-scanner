// SPDX-License-Identifier: EUPL-1.2

//
//  QRScannerManager.swift
//  QRCodeScannerPackage
//
//  Created by Matīss Mamedovs on 27/11/2024.
//
#if canImport(UIKit)

import Foundation
import AVFoundation
import UIKit

@MainActor final public class QRScannerManager: NSObject, Sendable {
    
    @MainActor fileprivate let captureSession: AVCaptureSession = AVCaptureSession()
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
    fileprivate var focusImageView: UIImageView?
    fileprivate var closeButton: UIButton?
    public static let shared = QRScannerManager()
    
    public weak var delegate: QRCodeActionDelegate?
    
    fileprivate var needCallback: Bool = true

    public func runSession(for parent: UIViewController) {
        needCallback = true
        self.addLayer(for: parent)
        DispatchQueue.global(qos: .background).async {
            Task { @MainActor in
                self.captureSession.startRunning()
                self.addViewFinder(parent: parent)
            }
        }
    }
    
    public func stopSession() {
        self.captureSession.stopRunning()
        self.removeLayer()
    }
    
    public func setUp() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                let output = AVCaptureMetadataOutput()

                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                
                if captureSession.canAddOutput(output) {
                    captureSession.addOutput(output)
                    output.metadataObjectTypes = [.qr]
                }
                
                
            } catch {
                // Device does not support reading QR code
                self.delegate?.showError(.noCamera)
                print(error)
            }
    }
}

extension QRScannerManager {
    fileprivate func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthorizationStatus {
        case .notDetermined:
            print("notDetermined")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("granted")
                DispatchQueue.main.async {
                    print("granted1")
                    completion(granted)
                }
            }
        case .restricted, .denied:
            completion(false)
        case .authorized:
            completion(true)
        @unknown default:
            completion(false)
        }
    }
    
    fileprivate func addLayer(for parent: UIViewController) {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            
            guard let previewLayer = previewLayer else { return }
            previewLayer.frame = parent.view.bounds
            
            parent.view.layer.addSublayer(previewLayer)
            
            guard let image = UIImage(named: "viewfinder") else {
                return
            }

            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            focusImageView = imageView
            
            closeButton = UIButton(type: .close)
            closeButton?.addTarget(self, action: #selector(close), for: .touchUpInside)
            closeButton?.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    @objc func close() {
        self.stopSession()
    }
    
    private func addViewFinder(parent: UIViewController) {
        guard let imageView = focusImageView else { return }

        parent.view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: parent.view.centerYAnchor),
            imageView.centerXAnchor.constraint(equalTo: parent.view.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 300),
            imageView.heightAnchor.constraint(equalToConstant: 300),
        ])
        
        guard let closeButton = closeButton else { return }
        
        parent.view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.leftAnchor.constraint(equalTo: parent.view.leftAnchor, constant: 30),
            closeButton.topAnchor.constraint(equalTo: parent.view.topAnchor, constant: 50),
            closeButton.widthAnchor.constraint(equalToConstant: 50),
            closeButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
    
    fileprivate func removeLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        focusImageView?.removeFromSuperview()
        focusImageView = nil
        closeButton?.removeFromSuperview()
        closeButton = nil
    }
    
}

extension QRScannerManager: AVCaptureMetadataOutputObjectsDelegate {
    
    nonisolated public func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  metadataObject.type == .qr,
                  let stringValue = metadataObject.stringValue else { return }
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        
        DispatchQueue.main.async(execute: {
            self.stopSession()
            if self.needCallback {
                self.needCallback = false
                self.delegate?.showQRCodeResult(result: stringValue)
            }
        })
    }
}

#endif

public protocol QRCodeActionDelegate: NSObject {
    func showError(_ error: ScanningError)
    func showQRCodeResult(result: String)
}
public enum ScanningError: Error {
    case noCamera
    case noPermission
}
