import Foundation
import HudCore

func runCameraTests() {
    print("\nCamera")

    test("zoom goes in and out by a camera's stops, within what the lens allows") {
        var c = HudSnapshot.Camera()
        c.maxZoom = 10
        expectEqual(c.zoom(stepping: 1), 1.5)
        c.zoom = 1.5
        expectEqual(c.zoom(stepping: 1), 2)
        expectEqual(c.zoom(stepping: -1), 1)
        c.zoom = 10
        expectEqual(c.zoom(stepping: 1), 10)
        c.zoom = 1
        expectEqual(c.zoom(stepping: -1), 1)
        c.maxZoom = 5
        c.zoom = 4
        expectEqual(c.zoom(stepping: 1), 5, "the lens's own top, not a stop past it")
        c.zoom = 2.7
        expectEqual(c.zoom(stepping: 1), 3, "from between stops, to the next one")
        expectEqual(c.zoom(stepping: -1), 2)
    }

    test("the zoom reads as a camera shows it") {
        var c = HudSnapshot.Camera()
        expectEqual(c.zoomTitle, "1\u{00D7}")
        c.zoom = 2.5
        expectEqual(c.zoomTitle, "2.5\u{00D7}")
        c.zoom = 3.999
        expectEqual(c.zoomTitle, "4\u{00D7}")
    }

    test("the camera is an app with a pad, between photos and the teleprompter") {
        expect(HudPanelKind.apps.contains(.camera))
        expect(HudPanelKind.camera.hasPhoneControls)
        let i = HudPanelKind.apps.firstIndex(of: .camera)!
        expectEqual(HudPanelKind.apps[i - 1], .photos)
    }

    test("the pad's buttons go to the Android phone as the camera's actions") {
        func wire(_ a: CameraAction) -> [String: Any] { RemoteWire.message(for: .camera(a)) ?? [:] }
        expectEqual(wire(.shutter)["a"] as? String, "camera")
        expectEqual(wire(.shutter)["c"] as? String, "shutter")
        expectEqual(wire(.mode(.magnify))["mode"] as? String, "magnify")
        expectEqual(wire(.zoom(-1))["by"] as? Int, -1)
        for (a, c) in [(CameraAction.flip, "flip"), (.freeze, "freeze"), (.light, "light"), (.bright, "bright")] {
            expectEqual(wire(a)["c"] as? String, c)
        }
    }

    test("the Android phone's camera reads here, its times as seconds ago") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = RemoteWire.camera(from: ["mode": "video", "status": "running", "zoom": 2.5, "maxZoom": 8,
                                         "front": false, "light": true, "recordingFor": 12.5, "shotAgo": 0.2,
                                         "notice": "SAVED TO PHOTOS"], now: now)
        expectEqual(c.mode, .video)
        expectEqual(c.zoom, 2.5)
        expectEqual(c.maxZoom, 8)
        expect(c.light)
        expectEqual(c.recordingSince, now.addingTimeInterval(-12.5))
        expectEqual(c.shotAt, now.addingTimeInterval(-0.2))
        expectEqual(c.notice, "SAVED TO PHOTOS")
        let idle = RemoteWire.camera(from: ["status": "paused"], now: now)
        expectEqual(idle.status, .paused)
        expect(!idle.isRecording)
        expectEqual(idle.zoom, 1)
        let state = RemoteWire.state(from: ["t": "state", "camera": ["mode": "magnify", "frozen": true]])
        expectEqual(state.camera.mode, .magnify)
        expect(state.camera.frozen)
        expect(state.applied(to: HudSnapshot()).camera.frozen, "into the snapshot the remote shows")
    }
}
