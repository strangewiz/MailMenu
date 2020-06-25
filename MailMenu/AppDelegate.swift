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

class AppDelegate: NSObject, NSApplicationDelegate {
  var controller: MailMenuController!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    controller = MailMenuController()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
  }

  @objc func quit() {
    NSApplication.shared.terminate(self)
  }
}
