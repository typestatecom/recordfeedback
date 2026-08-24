import Cocoa
import Carbon.HIToolbox

// Carbon hot keys need no Accessibility permission and a CGEventTap does, so a
// session starts without the user being sent to System Settings.
final class Hotkeys {
  static let shared = Hotkeys()
  private var handlers: [UInt32: () -> Void] = [:]
  private var refs: [EventHotKeyRef] = []
  private var nextID: UInt32 = 1

  func install() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
      var id = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &id)
      Hotkeys.shared.fire(id.id)
      return noErr
    }, 1, &spec, nil, nil)
  }

  func register(_ key: Shortcut, handler: @escaping () -> Void) {
    let id = nextID
    nextID += 1
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x52464244), id: id)
    let status = RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers,
                                     hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr || ref == nil {
      warn("could not register \(key.plain), another application already owns it.")
      warn("  fix: quit whatever owns \(key.plain), or change the key in the")
      warn("  overlay's settings, which the menu bar item opens.")
      return
    }
    handlers[id] = handler
    refs.append(ref!)
  }

  // A rebound key has to stop firing the thing it used to do, and Carbon keeps
  // the old registration alive until it is told otherwise.
  func unregisterAll() {
    for ref in refs { UnregisterEventHotKey(ref) }
    refs.removeAll()
    handlers.removeAll()
  }

  private func fire(_ id: UInt32) { handlers[id]?() }
}
