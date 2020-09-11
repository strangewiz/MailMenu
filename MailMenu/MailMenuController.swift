// Copyright 2020 Justin Cohen. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import UserNotifications
import os

protocol MenuBarUpdater {
  func updateAccounts(accounts: [Account])
  func updateMessages(account_id: Int, fullCount: Int, messages: [Message])
  func setupShowMail(account: Account, submenu: NSMenu)
}

extension URL {
  func valueOf(_ queryParamaterName: String) -> String? {
    guard let url = URLComponents(string: self.absoluteString) else { return nil }
    return url.queryItems?.first(where: { $0.name == queryParamaterName })?.value
  }
}

class MailMenuController: NSObject, MenuBarUpdater, UNUserNotificationCenterDelegate {
  var menu: NSMenu!
  var showWebViewMailSubmenu: NSMenu!
  var statusBarItem: NSStatusItem!
  let webController = WebController()
  var timer: Timer!
  var count = 0
  let emptyItem = NSMenuItem(title: "No Accounts Found", action: nil, keyEquivalent: "")

  lazy var chromeAccounts: [String: String] = {
    var dict: [String: String] = [:]
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    let directoryURL = appSupport?.appendingPathComponent("Google").appendingPathComponent("Chrome")
    let profilesToTry = ["Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"]
    for dir_name in profilesToTry {
      //var path = directoryURL?.appendingPathComponent("Profile " + String(index))
      var path = directoryURL?.appendingPathComponent(dir_name)
      if !fileManager.fileExists(atPath: path!.path) {
        continue
      }
      path = path?.appendingPathComponent("Preferences")
      let data = try? Data(contentsOf: path!, options: .mappedIfSafe)
      let json = try? JSONSerialization.jsonObject(with: data!, options: [])
      if let dictionary = json as? [String: Any] {
        if let array = dictionary["account_info"] as? [Any] {
          if let firstObject = array.first as? [String: Any] {
            let email: String = firstObject["email"] as! String
            dict[dir_name] = email
          }
        }
      }
    }
    return dict
  }()

  override init() {
    super.init()
    menu = NSMenu()

    let checkAllItem = NSMenuItem(
      title: "Check All", action: #selector(self.checkAll), keyEquivalent: "")
    checkAllItem.target = self
    menu.addItem(checkAllItem)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(emptyItem)

    menu.addItem(NSMenuItem.separator())

    let showWebViewItem = NSMenuItem(
      title: "Show Accounts", action: #selector(self.showWebViewAccounts), keyEquivalent: "")
    showWebViewItem.target = self
    menu.addItem(showWebViewItem)

    let showWebViewMailItem = NSMenuItem(
      title: "Show Mail", action: #selector(self.showWebViewMail), keyEquivalent: "")
    showWebViewMailItem.target = self
    menu.addItem(showWebViewMailItem)
    showWebViewMailSubmenu = NSMenu()
    menu.setSubmenu(showWebViewMailSubmenu, for: showWebViewMailItem)

    let quitItem = NSMenuItem(title: "Quit", action: #selector(self.quit), keyEquivalent: "")
    quitItem.target = self
    menu.addItem(quitItem)

    statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusBarItem.menu = menu
    statusBarItem.button?.cell?.isHighlighted = false
    updateCount()

    webController.delegate = self

    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(onWakeNote(note:)),
      name: NSWorkspace.didWakeNotification, object: nil)

    // Set up timer for 7 1/2 minutes
    timer = Timer.scheduledTimer(
      timeInterval: 450,
      target: self,
      selector: #selector(self.checkAll),
      userInfo: nil,
      repeats: true)

    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let options: UNAuthorizationOptions = [.alert]
    center.requestAuthorization(options: options) {
      (granted, error) in
      if !granted {
        print("Something went wrong")
      }
    }
  }

  @objc func onWakeNote(note: NSNotification) {
    // Check for mail and reset timer.
    self.checkAll()
    timer = Timer.scheduledTimer(
      timeInterval: 450,
      target: self,
      selector: #selector(self.checkAll),
      userInfo: nil,
      repeats: true)
  }

  func updateCount() {
    // iterate accounts plz
    count = 0
    for item in menu.items {
      guard let account = item.representedObject as? Account else {
        continue
      }
      count += account.fullCount
    }

    let attributedString = NSMutableAttributedString(string: "✉ \(count)")
    attributedString.addAttribute(
      NSAttributedString.Key.foregroundColor,
      value: NSColor.blue,
      range: NSMakeRange(0, 1))
    statusBarItem.button?.attributedTitle = attributedString
  }

  //MARK: MenuBarUpdater

  func updateAccounts(accounts: [Account]) {
    emptyItem.isHidden = false

    for item in menu.items {
      if item.representedObject != nil {
        menu.removeItem(item)
      }
    }

    for account in accounts {
      emptyItem.isHidden = true
      //      print("GOT account \(account.name!) with id \(account.id!)")
      let submenu = NSMenu()
      let accountItem = NSMenuItem(title: account.name, action: nil, keyEquivalent: "")
      accountItem.representedObject = account
      menu.insertItem(accountItem, at: menu.index(of: emptyItem))
      menu.setSubmenu(submenu, for: accountItem)
      setupShowMail(account: account, submenu: showWebViewMailSubmenu)
    }
    checkAll()
  }
  
  func setupShowMail(account: Account, submenu: NSMenu) {
    let showWebViewMailItem = NSMenuItem(
      title: "Load Mail for \(account.name!)", action: #selector(self.showWebViewMail), keyEquivalent: "")
    showWebViewMailItem.target = self
    showWebViewMailItem.representedObject = account
    submenu.addItem(showWebViewMailItem)
  }

  func updateMessages(account_id: Int, fullCount: Int, messages: [Message]) {
    if messages.count > 0 {
      os_log("updateMessages %d", messages.count)
      let message = messages.first!
      let firstTimestamp = message.timestamp!
      if firstTimestamp > message.account.latestTimestamp {

        //  how many new Message in messages have a .timestamp > newestDate
        let count = messages.filter { $0.timestamp > message.account.latestTimestamp }.count
        let content = UNMutableNotificationContent()
        content.title = message.account.name
        content.subtitle = String(count) + " unread messages"
        content.body = message.from + ": " + message.title
        content.sound = .default
        content.userInfo = [
          "link": message.link.absoluteString,
          "name": message.account.name!,
        ]
        let request = UNNotificationRequest(
          identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
      }
    } else {
      os_log("updateMessages zero.")
    }
    for item in menu.items {
      guard var account = item.representedObject as? Account else {
        continue
      }
      if account.id == account_id {
        item.submenu!.removeAllItems()
        item.title = account.name + " (\(fullCount))"
        account.fullCount = fullCount
        item.representedObject = account
        for message in messages {
          let messageTitle = message.from + ": " + message.title
          let messageItem = NSMenuItem(
            title: messageTitle, action: #selector(self.openMessageItem), keyEquivalent: "")
          messageItem.toolTip = message.summary
          messageItem.target = self
          messageItem.representedObject = message
          messageItem.isEnabled = true
          item.submenu?.addItem(messageItem)
        }
      }
    }

    updateCount()
  }

  //MARK: UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Do something here, either just open the default email account, or maybe the most recent message?
    let dict = response.notification.request.content.userInfo as Dictionary
    let url = URL(string: dict["link"] as! String)
    openMessage(link: url!, name: dict["name"] as! String)

    // Meh, not sure.  Clear them here why not.
    center.removeAllDeliveredNotifications()
  }
  //MARK: Actions

  @objc func checkAll() {
    os_log("checkAll")
    webController.getMail()
  }

  @objc func showWebViewAccounts() {
    webController.showAccounts()
  }

  @objc func showWebViewMail(_ sender: NSMenuItem) {
    guard let account = sender.representedObject as? Account else {
      return
    }

    webController.showMail(id: account.id)
  }

  @objc func openMessageItem(_ sender: NSMenuItem) {
    guard let message = sender.representedObject as? Message else {
      return
    }

    openMessage(link: message.link, name: message.account.name)
  }

  func openMessage(link: URL, name: String) {

    var profile: String = ""
    var chromeAccountFound: Bool = false
    let urlString: String = "https://mail.google.com/mail/u/\(name)/#inbox/" + link.valueOf("message_id")!
    
    // The following will only work if app sandbox is set to NO
    for (dir_name, email) in chromeAccounts {
      if email == name {
        profile = "--profile-directory=" + dir_name
        chromeAccountFound = true
        break
      }
    }
    
    let configuration = NSWorkspace.OpenConfiguration()
    var urls = [URL(string: urlString)!]
    if chromeAccountFound {
      configuration.createsNewApplicationInstance = true
      // Sad, this one line requires turning sandboxing off.
      configuration.arguments = [
        profile,  // e.g --profile-directory=Profile 1
        // Normally one woulduse NSWorkspace.open, but
        // profile above doesn't seem to work that way.
        urlString,
      ]
      urls = []
    }
      
    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")!
    // Note the empty [], so .arguments comment above.
    NSWorkspace.shared.open(
      urls,
      withApplicationAt: appURL,
      configuration: configuration,
      completionHandler: nil)
  }

  @objc func quit() {
    NSApplication.shared.terminate(self)
  }

}
