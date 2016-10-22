If you want to support my open source projects financially, you can do so by purchasing a copy of [BrowserFreedom](https://getbrowserfreedom.com) or [Mediunic](https://itunes.apple.com/app/mediunic-medium-client/id1088945121?mt=12) 😁

## ChromeCastCore: An open source implementation of the Google Cast SDK for macOS

This framework implements the Google Cast APIs so they can be used in macOS apps. Google provides an official SDK but it is only for iOS and closed source.

### 🔴 Project status: experimental

This project is currently on its infancy, I have only implemented the features I needed to support ChromeCast streaming on [Apple Events](https://github.com/insidegui/AppleEvents), but I plan on supporting more stuff in the future. The code is also not very well organized, needs some refactoring =]

### OS Support

I have only tested on 10.12, but it should work on 10.11 and even on iOS (with some minor changes).

### Building

**Important: you need automake, libtool and protobuf on your system to build this project, the easiest way to install them is by using [Homebrew](http://brew.sh).**

To build the framework, you need to clone this repository and its dependencies:

	$ git clone --recursive https://github.com/ChromeCastCore/ChromeCastCore.git && cd ChromeCastCore

After cloning, run the bootstrap script to build the dependencies:

	$ ./bootstrap.sh

### Basic usage

### Finding ChromeCast devices on the network

```swift
import ChromeCastCore

var scanner = CastDeviceScanner()

NotificationCenter.default.addObserver(forName: DeviceScanner.DeviceListDidChange, object: scanner, queue: nil) { [unowned self] _ in
	// self.scanner.devices contains the list of devices available
}
        
scanner.startScanning()
```

### Connecting to a device

`CastClient` is the class used to establish a connection and sending requests to a specific device, you instantiate it with a `CastDevice` instance received from `CastDeviceScanner`.

```swift
import ChromeCastCore

var client = CastClient(device: scanner.devices.first!)
client.connect()
```

### Getting information about status changes

`CastClient` currently implements two block-based callbacks for you to get notifications about status changes:

* `statusDidChange` is called when the device's overall status has changed (running apps, volume, etc)
* `mediaStatusDidChange` is called when the device's playback status has changed (current media item, current time, etc). NOTE: this is not called automatically during playback, you must send a request asking for the media info

You can also implement the `CastClientDelegate` protocol to get information about the connection and the device's status:

```swift
protocol CastClientDelegate {    
    optional func castClient(_ client: CastClient, willConnectTo device: CastDevice)
    optional func castClient(_ client: CastClient, didConnectTo device: CastDevice)
    optional func castClient(_ client: CastClient, didDisconnectFrom device: CastDevice)
    optional func castClient(_ client: CastClient, connectionTo device: CastDevice, didFailWith error: NSError)
    
    optional func castClient(_ client: CastClient, deviceStatusDidChange status: CastStatus)
    optional func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus)
}
```

### Launching an app

To launch an app on the device, you use the `launch` method on `CastClient`:

```swift
// .defaultMediaPlayer is the 'generic' player that can stream any video URL of a supported type
client.launch(appId: .defaultMediaPlayer) { [weak self] error, app in
    guard let app = app else {
        if let error = error {
            NSLog("Error launching app: \(error)")
        } else {
            NSLog("Unknown error launching app")
        }
        
        return
    }

    // here you would probably call client.load(...) to load some media with the app,
	// or hold onto the app instance to send commands to it later
}
```

Notice the `.defaultMediaPlayer` enum above, it represents the 'generic' player that can stream any supported video URL you send it. The framework only supports this and `.youTube` for now.

### Loading media

After you have an instance of `CastApp`, you can tell the client to load some media with it using the `load` method:

```swift
let videoURL = URL(string: "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8")!
let posterURL = URL(string: "https://i.imgur.com/GPgh0AN.jpg")!

// create a CastMedia object to hold media information
let media = CastMedia(title: "Test Bars", 
						url: videoURL, 
						poster: posterURL, 
						contentType: "application/vnd.apple.mpegurl", 
						streamType: CastMediaStreamType.buffered, 
						autoplay: true, 
						currentTime: 0)

// app is the instance of the app you got from the client after calling launch, or from the status callbacks
client.load(media: media, with: app) { error, status in
    guard let status = status else {
        if let error = error {
            NSLog("Error loading media: \(error)")
        } else {
            NSLog("Unknown error loading media")
        }
        
        return
    }
    
    // this media has been successfully loaded, status contains the initial status for this media
	// you can now call requestMediaStatus periodically to get updated media status
}
```

### Getting media status periodically

After you start streaming some media, you will probably want to get updated status every second, to update the UI. You should call the method `requestMediaStatus` on `CastClient`, this sends a request to the device to get the most recent media status, to get the response you must have registered a `mediaStatusDidChange` callback or implemented the `castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus)` delegate method.

```swift

func updateStatus() {
	// app is a CastApp instance you got after launching the app
	// mediaSessionId is the current media session id you got from the latest CastStatus
	client.requestMediaStatus(for: app, mediaSessionId: status.mediaSessionId)
}

func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus) {
	NSLog("media status did change: \(status)")
}
```