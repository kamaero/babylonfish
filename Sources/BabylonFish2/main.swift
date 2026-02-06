import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate2()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)