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

    getAccounts()
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
    showWindow()
    webView.load(URLRequest(url: URL(string: "https://accounts.google.com/signoutoptions?hl=en")!))
  }

  func showMail(id: Int) {
    showWindow()
    let url_string = "https://mail.google.com/mail/u/\(id)"
    webView.load(URLRequest(url: URL(string: url_string)!))
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
      let url_string = "https://mail.google.com/mail/u/\(account.id!)/feed/atom/%5Esq_ig_i_personal"
      os_log("fetching %@", url_string)
      WebCommand.fetch(
        url_string,
        completionHandler: { (html: Any?, error: Error?) in
          os_log("In completion handler")
          var messages = [Message]()
          var fullCount = 0
          let xml = try! XML.parse(html as! String)
          os_log("In completion handler %@", url_string)
          if xml["html"].element != nil {
            // fire an error here, most likely unuathorized.
            os_log("auth error %@", url_string)
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
          self.delegate.updateMessages(
            account_id: account.id, fullCount: fullCount, messages: messages)
          
          // TODO: This crashed, maybe accounts[index] is wrong? or no messages?
          // blech.
          if messages.isEmpty == false {
            self.accounts[index].latestTimestamp = messages.first!.timestamp!
          }
        })
    }
  }

  func getAccounts() {
    let handleAccounts = { (html: Any?, error: Error?) in
      // print(html!)
      let pattern = "choose-account-(.)\" .* value=\"(.*)\">"
      let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
      let htmlString = html as! String
      let range = NSRange(location: 0, length: htmlString.utf16.count)
      regex?.enumerateMatches(in: htmlString, options: [], range: range) { (match, _, stop) in
        guard let match = match else { return }
        if match.numberOfRanges == 3 {
          let firstCaptureRange = Range(match.range(at: 1), in: htmlString)
          let secondCaptureRange = Range(match.range(at: 2), in: htmlString)
          //          print(htmlString[firstCaptureRange!])
          //          print(htmlString[secondCaptureRange!])
          var account = Account()
          account.id = Int(htmlString[firstCaptureRange!])
          account.name = String(htmlString[secondCaptureRange!])
          self.accounts.append(account)
        } else {
          print("Error getAccounts.")
        }
      }
      self.delegate.updateAccounts(accounts: self.accounts)
    }
    accounts.removeAll()
    WebCommand.fetch(
      "https://accounts.google.com/signoutoptions?hl=en",
      completionHandler: handleAccounts)
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
