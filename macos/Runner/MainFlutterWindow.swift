import Cocoa
import FlutterMacOS
import MediaPlayer

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Set window properties
    self.title = "Music Player"
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    self.backgroundColor = NSColor.clear
    self.isOpaque = false
    self.hasShadow = true
    
    // Enable window state persistence
    self.setFrameAutosaveName("MusicPlayerWindow")
    
    // Set window style
    self.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    
    // Set window level
    self.level = .normal
    
    // Set window collection behavior
    self.collectionBehavior = [.managed, .fullScreenAuxiliary]

    // Set up media controls
    setupMediaControls(flutterViewController: flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
  
  override func windowWillClose(_ notification: Notification) {
    // Save window state before closing
    self.saveFrame(usingName: "MusicPlayerWindow")
    super.windowWillClose(notification)
  }

  private func setupMediaControls(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.cresca.media_controls",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      switch call.method {
      case "updateMediaControls":
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String,
              let album = args["album"] as? String,
              let duration = args["duration"] as? Int64,
              let position = args["position"] as? Int64,
              let isPlaying = args["isPlaying"] as? Bool else {
          result(FlutterError(code: "INVALID_ARGUMENTS",
                            message: "Invalid arguments",
                            details: nil))
          return
        }

        self.updateNowPlayingInfo(
          title: title,
          artist: artist,
          album: album,
          duration: duration,
          position: position,
          isPlaying: isPlaying
        )
        result(nil)

      case "dispose":
        self.cleanupMediaControls()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Set up remote control event handling
    NSApp.becomeFirstResponder()
    NSApp.nextResponder = self
  }

  private func updateNowPlayingInfo(
    title: String,
    artist: String,
    album: String,
    duration: Int64,
    position: Int64,
    isPlaying: Bool
  ) {
    var nowPlayingInfo = [String: Any]()
    
    nowPlayingInfo[MPMediaItemPropertyTitle] = title
    nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(duration) / 1000.0
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(position) / 1000.0
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func cleanupMediaControls() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  override func remoteControlReceived(with event: NSEvent?) {
    guard let event = event else { return }

    switch event.subtype {
    case .remoteControlPlay:
      sendMediaControlEvent("playPause")
    case .remoteControlPause:
      sendMediaControlEvent("playPause")
    case .remoteControlNextTrack:
      sendMediaControlEvent("next")
    case .remoteControlPreviousTrack:
      sendMediaControlEvent("previous")
    case .remoteControlStop:
      sendMediaControlEvent("stop")
    default:
      break
    }
  }

  private func sendMediaControlEvent(_ event: String) {
    guard let flutterViewController = contentViewController as? FlutterViewController else { return }
    
    let channel = FlutterMethodChannel(
      name: "com.cresca.media_controls",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    channel.invokeMethod(event, arguments: nil)
  }
}
