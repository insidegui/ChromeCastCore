//
//  ViewController.swift
//  ChromeCastDemo
//
//  Created by Guilherme Rambo on 22/04/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Cocoa
import ChromeCastCore

class ViewController: NSViewController, CastClientDelegate {

    @IBOutlet weak var mediaField: NSTextField!

    @IBOutlet weak var castButton: NSButton! {
        didSet {
            castButton.isEnabled = false
        }
    }

    @IBOutlet var consoleView: NSTextView! {
        didSet {
            consoleView.backgroundColor = .black
            consoleView.isEditable = false
        }
    }

    private let scanner = CastDeviceScanner()

    private var selectedDevice: CastDevice? {
        didSet {
            validateInputs()
        }
    }

    private var devicesObserver: NSObjectProtocol?

    private var mediaURL: URL? {
        didSet {
            validateInputs()
        }
    }

    private func validateInputs() {
        castButton.isEnabled = selectedDevice != nil && mediaURL != nil
    }

    private func updateMediaURL() {
        guard let str = mediaField?.stringValue else { return }

        mediaURL = URL(string: str)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        devicesObserver = NotificationCenter.default.addObserver(forName: CastDeviceScanner.DeviceListDidChange, object: scanner, queue: .main) { [weak self] _ in
            self?.deviceListDidChange()
        }

        scanner.startScanning()
        updateMediaURL()
    }

    private func deviceListDidChange() {
        consoleLog("Device list did change. Have \(scanner.devices.count) device(s).\n\(scanner.devices)")

        selectedDevice = scanner.devices.first
    }

    @IBAction func mediaFieldTextDidChange(_ sender: NSTextField) {
        updateMediaURL()
    }

    private var client: CastClient?

    @IBAction func cast(_ sender: NSButton) {
        guard let device = selectedDevice else { return }

        client = CastClient(device: device)
        client?.delegate = self
        client?.connect()
    }

    private func loadMedia() {
        guard let url = mediaURL else { return }
        guard let poster = URL(string: "https://devimages-cdn.apple.com/wwdc-services/images/7/1671/1671_wide_250x141_2x.jpg") else { return }

        let media = CastMedia(
            title: "Test",
            url: url,
            poster: poster,
            contentType: "application/vnd.apple.mpegurl",
            streamType: .buffered,
            autoplay: true,
            currentTime: 0
        )

        client?.launch(appId: .defaultMediaPlayer) { [weak self] error, app in
            if let error = error {
                self?.consoleLog("Failed to launch media player: \(String(describing: error))")
                return
            }

            guard let app = app else {
                self?.consoleLog("No error, but app was nil. What?!")
                return
            }

            self?.client?.load(media: media, with: app) { error, mediaStatus in
                if let error = error {
                    self?.consoleLog("Failed to load media with default media player: \(String(describing: error))")
                    return
                } else {
                    self?.consoleLog("Media loaded")
                }
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        view.window?.appearance = NSAppearance(named: .vibrantDark)
        view.window?.title = "ChromeCastCore Demo"
    }

    private let consoleAttributes: [NSAttributedStringKey: Any] = {
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.lightGray
        ]
    }()

    private func consoleLog(_ msg: String) {
        let attributedMessage = NSAttributedString(string: msg + "\n", attributes: consoleAttributes)

        consoleView.textStorage?.append(attributedMessage)

        consoleView.scrollToEndOfDocument(nil)
    }

    deinit {
        if let observer = devicesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CastClientDelegate

    @objc func castClient(_ client: CastClient, willConnectTo device: CastDevice) {
        consoleLog("Will connect to \(device)")
    }

    @objc func castClient(_ client: CastClient, didConnectTo device: CastDevice) {
        consoleLog("Now connected to \(device)")

        loadMedia()
    }

    @objc func castClient(_ client: CastClient, didDisconnectFrom device: CastDevice) {
        consoleLog("! Disconnected from \(device)")
    }

    @objc func castClient(_ client: CastClient, connectionTo device: CastDevice, didFailWith error: NSError) {
        consoleLog("! Connection to \(device.name) failed with error \(String(describing: error))")
    }

    @objc func castClient(_ client: CastClient, deviceStatusDidChange status: CastStatus) {
        consoleLog("Device status changed:\n\(status)")
    }

    @objc func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus) {
        consoleLog("Media status changed:\n\(status)")
    }

}
