//
//  ViewController.swift
//  ChromeCastDemo
//
//  Created by Guilherme Rambo on 22/04/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Cocoa
import ChromeCastCore

class ViewController: NSViewController {

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

    @IBAction func cast(_ sender: NSButton) {

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
        consoleView.textStorage?.append(NSAttributedString(string: msg, attributes: consoleAttributes))
        consoleView.scrollToEndOfDocument(nil)
    }

    deinit {
        if let observer = devicesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }


}

