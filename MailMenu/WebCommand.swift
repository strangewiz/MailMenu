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

import Foundation
import WebKit

/// A helper class that loads a URL and calls a completion handler with the page contents or an error.
/// TODO: Error handling on page failures, or general timeouts...
class WebCommand: NSObject, WKNavigationDelegate {
  var webView: WKWebView!
  var completionHandler: ((String?, Error?) -> Void)
  static var commands = Set<WebCommand>()

  override init() {
    webView = WKWebView(frame: CGRect.zero, configuration: WKWebViewConfiguration())
    completionHandler = { (html: Any?, error: Error?) in }
    super.init()
    webView.navigationDelegate = self
  }

  static func fetch(_ url: String, completionHandler: ((String?, Error?) -> Void)? = nil) {
    let command = WebCommand()
    command.completionHandler = completionHandler!
    command.webView.load(URLRequest(url: URL(string: url)!))
    WebCommand.commands.insert(command)
  }

  // MARK: WKNavigationDelegate

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.evaluateJavaScript(
      "document.documentElement.outerHTML.toString()",
      completionHandler: { (html: Any?, error: Error?) in
        self.completionHandler(html as? String, nil)
        WebCommand.commands.remove(self)
      })
  }

  // Do something to remove commands that fail, or timeout..
  public func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {

  }
}
