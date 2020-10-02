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

import Cocoa
import Foundation
import SwiftyXMLParser
import WebKit
import os
import CryptoSwift
import SQLite


extension String {
    func trim() -> String {
          return self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}


class ViewController: NSViewController {
  override func loadView() {
    view = NSView()
  }
}

/// A hackarific class to
class WebController: NSObject, NSWindowDelegate, WKNavigationDelegate {

  var window: NSWindow!
  var webView: WKWebView!
  var delegate: MenuBarUpdater!
  var accounts = [Account]()

  override init() {
    super.init()

    // TODO::
    // Configure some buttons to load the accounts chooser, and gmail for each
    // account found.  Need to load gmail once otherwise we will get an
    // unauthorized error.
  }

  func showWindow() {
    if window == nil {
      window = NSWindow(contentViewController: ViewController())
      window.delegate = self
      window.title = "Configure Gmail Accounts Here"
      window.styleMask = [.closable, .titled, .miniaturizable, .resizable]
      window.backingType = .buffered
      window.level = .floating
      window.setFrame(NSRect(x: 700, y: 200, width: 500, height: 500), display: false)

      webView = WKWebView(
        frame: window.contentViewController!.view.bounds, configuration: WKWebViewConfiguration())
      webView.navigationDelegate = self
      webView.translatesAutoresizingMaskIntoConstraints = false
      webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.1 Safari/605.1.15"
      webView.autoresizingMask = [.width, .height];
      window.contentViewController!.view.addSubview(webView)
    }
    window.makeKeyAndOrderFront(self)
  }

  func showAccounts() {
//    showWindow()
//    webView.load(URLRequest(url: URL(string: "https://accounts.google.com/signoutoptions?hl=en")!))
  }

  func showMail(id: Int) {
//    showWindow()
//    let url_string = "https://mail.google.com/mail/u/\(id)"
//    webView.load(URLRequest(url: URL(string: url_string)!))
  }

  func getMail() {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

    // No error handling, look for unauthorized especially!
    // another way to do this would be
    // self.accounts = self.accounts.map { account in
    for (index, account) in self.accounts.enumerated() {

      /*
       ^sq_ig_i_personal (Inbox Primary),
       ^sq_ig_i_social (Inbox Social),
       ^sq_ig_i_promo (Inbox Promotions),
       ^sq_ig_i_notification (Inbox Updates),
       ^sq_ig_i_group (Inbox Forums)
       */
      
      let cookieStore = HTTPCookieStorage.shared
      for cookie in cookieStore.cookies ?? [] {
          cookieStore.deleteCookie(cookie)
      }

      let url = URL(string: "https://mail.google.com/mail/u/0/feed/atom/%5Esq_ig_i_personal")!
//      let jar = HTTPCookieStorage.shared
//      let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": account.cookies], for: url)
//      jar.setCookies(cookies, for: url, mainDocumentURL: url)
      let url_request =  NSMutableURLRequest(url: url)
      url_request.addValue(account.cookies, forHTTPHeaderField: "cookie")

      // Then
      let task = URLSession.shared.dataTask(with: url_request as URLRequest) {(data, response, error) in
          guard let data = data else { return }
          let html = String(data: data, encoding: .utf8)!
          os_log("In completion handler")
          var messages = [Message]()
          var fullCount = 0
          let xml = try! XML.parse(html as! String)
        os_log("In completion handler %@", url.absoluteString)
          if xml["html"].element != nil {
            // fire an error here, most likely unuathorized.
            os_log("auth error %@", url.absoluteString)
            self.showMail(id: account.id)
            return;
          }
          let count = xml["feed"]["fullcount"].int
          if count != nil {
            fullCount = count!
            os_log("Got a count of %d", fullCount)
          } else {
            os_log("Got a nil count")
          }

          for entry in xml["feed", "entry"] {
            var message = Message()
            message.title = String(entry["title"].text ?? "")
            message.from = String(entry["author"]["name"].text ?? "")
            message.summary = String(entry["summary"].text ?? "")

            let isoDate = String(entry["modified"].text!)
            message.timestamp = dateFormatter.date(from: isoDate)!

            // TODO: need to trim mail/u/N with mail
            // This is dumb.
            let url =
              "https://mail.google.com/mail/?account_id\(entry["link"].attributes["href"]!.components(separatedBy: "account_id")[1])"
            message.link = URL(string: url)
            message.account = account
            //              print("Got a title of of : \(message.title!)")
            messages.append(message)
          }
        DispatchQueue.main.async {
          self.delegate.updateMessages(
            account_name: account.name, fullCount: fullCount, messages: messages)
        }

          // TODO: This crashed, maybe accounts[index] is wrong? or no messages?
          // blech.
          if messages.isEmpty == false {
            self.accounts[index].latestTimestamp = messages.first!.timestamp!
          }
      }
      os_log("fetching %@", url.absoluteString)
      task.resume()
    }
  }
  
  func decrypt(key:Array<UInt8>, salt:Array<UInt8>, encryptedBytes:Array<UInt8>) -> String {
    // The encrypted data start with the ASCII encoding of v10 (i.e. 0x763130),
    // followed by the 12 bytes nonce, the actual ciphertext and finally the 16
    // bytes authentication tag. The individual components can be separated as
    // follows:
    //    nonce = data[3:3+12]
    //    ciphertext = data[3+12:-16]
    //    tag = data[-16:]
    let begin = 3
    let ciphertext = encryptedBytes[begin...]
    let iv = Array("                ".utf8)
    let decrypted = try! AES(key: key, blockMode: CBC(iv: iv), padding: .pkcs5).decrypt(ciphertext)
    if let string = String(bytes: decrypted, encoding: .utf8) {
      return string
    } else {
      return "not a valid UTF-8 sequence"
    }
  }

  func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    return output.trim()
  }
  
  func getCookies(path:String) -> String {
    let key = shell("security find-generic-password -a 'Chrome' -w")
    let password: Array<UInt8> = Array(key.utf8)
    let salt: Array<UInt8> = Array("saltysalt".utf8)

    let keyData = try! PKCS5.PBKDF2(password: password, salt: salt, iterations: 1003, keyLength: 16, variant: .sha1).calculate()

    var set_cookies:String = ""
    let db = try! Connection(path)
    for row in try! db.prepare("select name, encrypted_value from cookies where host_key like 'mail.google.com'") {
      let name = row[0] as! String
      let encrypted_blob:Blob = row[1] as! Blob
      let unencrypted:String = decrypt(key: keyData, salt: salt, encryptedBytes: encrypted_blob.bytes)
      set_cookies += "\(name)=\(unencrypted); "
    }
    for row in try! db.prepare("select name, encrypted_value from cookies where host_key like '.google.com'") {
      let name = row[0] as! String
      let encrypted_blob:Blob = row[1] as! Blob
      let unencrypted:String = decrypt(key: keyData, salt: salt, encryptedBytes: encrypted_blob.bytes)
      set_cookies += "\(name)=\(unencrypted); "
    }
    
    if (!set_cookies.contains("SIDCC") || !set_cookies.contains("COMPASS")) {
      return String();
    }
    return set_cookies
  }

  func getAccounts() {
    accounts.removeAll()

    var dict: [String: String] = [:]
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    let directoryURL = appSupport?.appendingPathComponent("Google").appendingPathComponent("Chrome")
    let profilesToTry = ["Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"]
    for dir_name in profilesToTry {
      var path = directoryURL?.appendingPathComponent(dir_name)
      if !fileManager.fileExists(atPath: path!.path) {
        continue
      }
      var preference_path = path?.appendingPathComponent("Preferences")
      let data = try? Data(contentsOf: preference_path!, options: .mappedIfSafe)
      let json = try? JSONSerialization.jsonObject(with: data!, options: [])
      if let dictionary = json as? [String: Any] {
        if let array = dictionary["account_info"] as? [Any] {
          if let firstObject = array.first as? [String: Any] {
            let email: String = firstObject["email"] as! String
            var cookies_path = path?.appendingPathComponent("Cookies")
            let cookies:String = getCookies(path: cookies_path!.path)
            if (cookies != nil) {
              var account = Account()
              account.name = email
              account.cookies = cookies
              self.accounts.append(account)
//              break
            }
          }
        }
      }
    }
    self.delegate.updateAccounts(accounts: self.accounts)
  }

  // MARK: NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    window.orderOut(self)
    getAccounts()
    return false
  }

  // MARK: WKNavigationDelegate

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // TODO maybe handle some errors.
    //    webView.evaluateJavaScript("document.documentElement.outerHTML.toString()",
    //                               completionHandler: { (html: Any?, error: Error?) in
    ////      print(html!)
    //    })
  }

  public func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {

  }
}
