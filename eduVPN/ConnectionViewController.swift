//
//  ConnectionViewController.swift
//  eduVPN
//
//  Created by Johan Kool on 28/06/2017.
//  Copyright © 2017 eduVPN. All rights reserved.
//

import Cocoa
import AppAuth
import Kingfisher

class ConnectionViewController: NSViewController {
    
    @IBOutlet var backButton: NSButton!
    @IBOutlet var stateImageView: NSImageView!
    @IBOutlet var locationImageView: NSImageView!
    @IBOutlet var profileLabel: NSTextField!
    @IBOutlet var spinner: NSProgressIndicator!
    @IBOutlet var disconnectButton: NSButton!
    @IBOutlet var connectButton: NSButton!
    @IBOutlet var statisticsBox: NSBox!
    @IBOutlet var notificationsBox: NSBox!
    @IBOutlet var notificationsField: NSTextField!
    
    var profile: Profile!
    var authState: OIDAuthState!
    @objc var statistics: Statistics?
    private var systemMessages: [Message] = []
    private var userMessages: [Message] = []
    
    @IBOutlet var statisticsController: NSObjectController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Change title color
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes = [NSAttributedStringKey.font: NSFont.systemFont(ofSize: 17), NSAttributedStringKey.foregroundColor : NSColor.white, NSAttributedStringKey.paragraphStyle : paragraphStyle]
        connectButton.attributedTitle = NSAttributedString(string: connectButton.title, attributes: attributes)
        disconnectButton.attributedTitle = NSAttributedString(string: disconnectButton.title, attributes: attributes)
        
        locationImageView?.kf.setImage(with: profile.info.provider.logoURL)
        profileLabel.stringValue = profile.displayName
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        updateForStateChange()
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged(notification:)), name: ConnectionService.stateChanged, object: ServiceContainer.connectionService)
        
        // Fetch messages
        ServiceContainer.providerService.fetchMessages(for: profile.info, audience: .system, authState: authState) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    self.systemMessages = messages
                    self.updateMessages()
                case .failure:
                    // Ignore
                    break
                }
            }
        }
        
        ServiceContainer.providerService.fetchMessages(for: profile.info, audience: .user, authState: authState) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    self.userMessages = messages
                    self.updateMessages()
                case .failure:
                    // Ignore
                    break
                }
            }
        }
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        NotificationCenter.default.removeObserver(self, name: ConnectionService.stateChanged, object: ServiceContainer.connectionService)
    }
    
    private func updateForStateChange() {
        switch ServiceContainer.connectionService.state {
        case .connecting:
            self.backButton.isHidden = true
            self.stateImageView.image = #imageLiteral(resourceName: "connecting")
            self.spinner.startAnimation(self)
            self.disconnectButton.isHidden = true
            self.connectButton.isHidden = true
            self.statisticsBox.isHidden = false
            
        case .connected:
            self.backButton.isHidden = true
            self.stateImageView.image = #imageLiteral(resourceName: "connected")
            self.spinner.stopAnimation(self)
            self.disconnectButton.isHidden = false
            self.connectButton.isHidden = true
            self.statisticsBox.isHidden = false
            self.startUpdatingStatistics()
            
        case .disconnecting:
            self.backButton.isHidden = true
            self.stateImageView.image = #imageLiteral(resourceName: "connecting")
            self.spinner.startAnimation(self)
            self.disconnectButton.isHidden = true
            self.connectButton.isHidden = true
            self.statisticsBox.isHidden = false
            self.stopUpdatingStatistics()
            
        case .disconnected:
            self.backButton.isHidden = false
            self.stateImageView.image = #imageLiteral(resourceName: "disconnected")
            self.spinner.stopAnimation(self)
            self.disconnectButton.isHidden = true
            self.connectButton.isHidden = false
            self.statisticsBox.isHidden = false
            self.stopUpdatingStatistics()
            
        }
    }
    
    @objc private func stateChanged(notification: NSNotification) {
        DispatchQueue.main.async {
            self.updateForStateChange()
        }
    }
    
    func connect(twoFactor: TwoFactor? = nil) {
        statisticsController.content = nil
        
        // Prompt user if we need two factor authentication token
        if profile.twoFactor, twoFactor == nil {
            let enter2FAViewController = storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "Enter2FA")) as! Enter2FAViewController
            enter2FAViewController.delegate = self
            mainWindowController?.present(viewController: enter2FAViewController)
            return
        }
        
        ServiceContainer.connectionService.connect(to: profile, twoFactor: twoFactor, authState: authState) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: self.view.window!) { (_) in
                        self.updateForStateChange()
                    }
                }
            }
        }
    }
    
    private func disconnect() {
        ServiceContainer.connectionService.disconnect() { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: self.view.window!) { (_) in
                        self.updateForStateChange()
                    }
                }
            }
        }
    }
    
    private func updateMessages() {
        let messages = userMessages + systemMessages
        notificationsBox.title = messages.count == 1 ? NSLocalizedString("Notification", comment: "Notification box title (1 message)") : NSLocalizedString("Notifications", comment: "Notifications box title")
        notificationsBox.isHidden = messages.isEmpty
        
        notificationsField.attributedStringValue = messages.reduce(into: NSMutableAttributedString()) { (notifications, message) in
            let date =  DateFormatter.localizedString(from: message.date, dateStyle: .short, timeStyle: .short)
            notifications.append(NSAttributedString(string: date + ": ", attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .small))]))
            notifications.append(NSAttributedString(string: message.message + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))]))
        }
    }
    
    private var statisticsTimer: Timer?
    
    private func startUpdatingStatistics() {
        statisticsTimer?.invalidate()
        if #available(OSX 10.12, *) {
            statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { (_) in
                self.readStatistics()
            }
        } else {
            // Fallback on earlier versions
            statisticsTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateStatistics(timer:)), userInfo: nil, repeats: true)
        }
    }
    
    @objc private func updateStatistics(timer: Timer) {
        if #available(OSX 10.12, *) {
            fatalError("This method is for backwards compatability only. Remove when deployment target is increased to 10.12 or later.")
        } else {
            // Fallback on earlier versions
            readStatistics()
        }
    }
    
    private func stopUpdatingStatistics() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
    }
    
    private func readStatistics() {
        ServiceContainer.connectionService.readStatistics { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let statistics):
                    self.statisticsController.content = statistics
                case .failure:
                    break
                }
            }
        }
    }
    
    @objc @IBAction func connect(_ sender: Any) {
        connect()
    }
    
    @objc @IBAction func disconnect(_ sender: Any) {
        disconnect()
    }
    
    @objc @IBAction func viewLog(_ sender: Any) {
        guard let logURL = ServiceContainer.connectionService.logURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(logURL)
    }
    
    @IBAction func goBack(_ sender: Any) {
        assert(ServiceContainer.connectionService.state == .disconnected)
        mainWindowController?.popToRoot()
    }
    
}

extension ConnectionViewController: Enter2FAViewControllerDelegate {
    
    func enter2FA(controller: Enter2FAViewController, enteredTwoFactor twoFactor: TwoFactor) {
        mainWindowController?.dismiss {
            self.connect(twoFactor: twoFactor)
        }
    }
    
    func enter2FACancelled(controller: Enter2FAViewController) {
        mainWindowController?.dismiss()
    }
    
}