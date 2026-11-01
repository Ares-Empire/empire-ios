// Sets a Core Animation debug option on a simulator (what the old Simulator.app's Debug menu did).
// usage: swiftc -O -o cadebug cadebug.swift; ./cadebug <udid> <option> <on|off> (offscreens.sh does both)
// Options on iOS 27.0: 0 CA_COLOR_FLUSH, 2 CA_COLOR_OPAQUE, 17 CA_COLOR_OFFSCREEN, 28 CA_COLOR_BACKDROPS, 31 CA_PRINT_OFFSCREENS.
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: cadebug <udid> <option> <on|off>"); exit(2) }
let udid = args[1], option = UInt32(args[2])!, enabled = args[3] == "on"
guard dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW) != nil else {
    print("no CoreSimulator"); exit(1)
}
let developerDir = "/Applications/Xcode.app/Contents/Developer"
guard let contextClass = NSClassFromString("SimServiceContext") as? NSObject.Type else { print("no SimServiceContext"); exit(1) }
let sharedSel = NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")
typealias SharedFn = @convention(c) (AnyObject, Selector, NSString, UnsafeMutablePointer<NSError?>?) -> AnyObject?
let sharedImp = method_getImplementation(class_getClassMethod(contextClass, sharedSel)!)
var error: NSError?
guard let context = unsafeBitCast(sharedImp, to: SharedFn.self)(contextClass, sharedSel, developerDir as NSString, &error) else {
    print("context failed: \(String(describing: error))"); exit(1)
}
let setSel = NSSelectorFromString("defaultDeviceSetWithError:")
typealias SetFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> AnyObject?
let setImp = class_getMethodImplementation(object_getClass(context), setSel)!
guard let deviceSet = unsafeBitCast(setImp, to: SetFn.self)(context, setSel, &error) as? NSObject else {
    print("device set failed: \(String(describing: error))"); exit(1)
}
let devices = deviceSet.value(forKey: "devices") as? [NSObject] ?? []
guard let device = devices.first(where: { ($0.value(forKey: "UDID") as? UUID)?.uuidString == udid }) else {
    print("device not found"); exit(1)
}
let optSel = NSSelectorFromString("setCADebugOption:enabled:")
typealias OptFn = @convention(c) (AnyObject, Selector, UInt32, Bool) -> Void
let optImp = class_getMethodImplementation(object_getClass(device), optSel)!
unsafeBitCast(optImp, to: OptFn.self)(device, optSel, option, enabled)
let getSel = NSSelectorFromString("getCADebugOption:")
typealias GetFn = @convention(c) (AnyObject, Selector, UInt32) -> Bool
let getImp = class_getMethodImplementation(object_getClass(device), getSel)!
let now = unsafeBitCast(getImp, to: GetFn.self)(device, getSel, option)
print("option \(option) set \(enabled), now \(now)")
