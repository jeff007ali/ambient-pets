import AppKit
import PetPlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = PetEngine()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // LSUIElement covers the bundled app; this also keeps an unbundled `swift run` out of the Dock.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--context-probe") {
            // Dev: print what the context monitors see, then quit.
            print(engine.contextProbe())
            exit(0)
        }
        engine.start()
        Onboarding.showIfFirstRun()
        devSummon()
    }

    /// Dev loop: `--summon ironman/emergency_landing` plays one scene at launch; `--summon all` cycles every scene;
    /// `--summon together` plays several pets at once; `--summon spiderman` cycles one pet's scenes.
    private func devSummon() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--summon"), i + 1 < args.count else { return }
        let target = args[i + 1]
        if target.hasPrefix("routine:") {
            // routine:<pet>:<block>,<block>,…
            let parts = target.split(separator: ":").map(String.init)
            if parts.count == 3 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    engine.summonRoutine(petID: parts[1], blocks: parts[2].split(separator: ",").map(String.init))
                }
            }
            return
        }
        if target.hasPrefix("ensemble:") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                engine.summonEnsemble(String(target.dropFirst("ensemble:".count)))
            }
            return
        }
        if target == "together" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                engine.summonTogether()
            }
            return
        }
        if let pack = engine.packs.first(where: { $0.id == target }) {
            Task { @MainActor in
                for scene in pack.data.scenes {
                    try? await Task.sleep(for: .seconds(1))
                    engine.summon(petID: pack.id, sceneID: scene.id)
                    while engine.isPlaying { try? await Task.sleep(for: .milliseconds(200)) }
                }
            }
            return
        }
        let queue: [(String, String)] = target == "all"
            ? engine.packs.flatMap { p in p.data.scenes.map { (p.id, $0.id) } }
            : [target.split(separator: "/").map(String.init)].compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        Task { @MainActor in
            for (pet, scene) in queue {
                try? await Task.sleep(for: .seconds(1))
                engine.summon(petID: pet, sceneID: scene)
                while engine.isPlaying { try? await Task.sleep(for: .milliseconds(200)) }
            }
        }
    }
}
