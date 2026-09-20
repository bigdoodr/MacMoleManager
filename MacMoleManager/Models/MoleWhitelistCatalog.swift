//
//  MoleWhitelistCatalog.swift
//  MacStorageManager
//
//  The menu Mole's own interactive `mole clean --whitelist` presents, ported
//  verbatim (name, pattern, category, order) from `get_all_cache_items()` in
//  lib/manage/whitelist.sh. Source: tw93/Mole, commit 650ec4202343542e86b09c451a75bd6c171b5b6e.
//
//  Left out on purpose: four dynamic rows (Go/GitHub CLI/Clang caches) that
//  script only adds when it detects the underlying tool on the Mac. Anyone
//  who wants one protected can add its path manually below.
//
//  Patterns keep Mole's literal "$HOME" text as authored; `expandedPattern`
//  swaps that for the real home directory at load/save time, mirroring
//  whitelist.sh's own `pattern="${pattern/\$HOME/$HOME}"`.
//

import Foundation

struct WhitelistCatalogItem: Identifiable, Hashable {
    let name: String
    /// As authored in Mole's source — may still contain the literal text
    /// "$HOME"; use `expandedPattern` for the value that actually belongs
    /// in the config file or gets compared against it.
    let rawPattern: String
    let category: WhitelistCategory
    /// Mole force-merges a small set of hard-safety patterns into every
    /// whitelist file regardless of user choice (lib/core/base.sh's
    /// `SAFETY_WHITELIST_PATTERNS`); these rows are the closest match, shown
    /// checked and disabled since unchecking one would be purely cosmetic.
    let isAlwaysProtected: Bool

    var id: String { rawPattern }

    var expandedPattern: String {
        rawPattern.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
    }
}

enum WhitelistCategory: String, CaseIterable {
    case system = "system_cache"
    case ide = "ide_cache"
    case aiml = "ai_ml_cache"
    case compiler = "compiler_cache"
    case packageManager = "package_manager"
    case browser = "browser_cache"
    case network = "network_tools"
    case container = "container_cache"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .ide: return "IDEs & Editors"
        case .aiml: return "AI / ML Tools"
        case .compiler: return "Compilers & Build Tools"
        case .packageManager: return "Package Managers"
        case .browser: return "Browsers"
        case .network: return "Network Tools"
        case .container: return "Containers & VMs"
        }
    }
}

enum MoleWhitelistCatalog {

    static let items: [WhitelistCatalogItem] = [
        item("Apple Mail cache", "$HOME/Library/Caches/com.apple.mail/*", .system),
        item("Gradle build cache (Android Studio, Gradle projects)", "$HOME/.gradle/caches/build-cache-*/*", .ide),
        item("Gradle daemon processes cache", "$HOME/.gradle/daemon/*", .ide),
        item("Gradle worker cache", "$HOME/.gradle/workers/*", .ide),
        item("Xcode DerivedData (build outputs, indexes)", "$HOME/Library/Developer/Xcode/DerivedData/*", .ide),
        item("Xcode internal cache files", "$HOME/Library/Caches/com.apple.dt.Xcode/*", .ide),
        item("Xcode iOS device support symbols", "$HOME/Library/Developer/Xcode/iOS DeviceSupport/*/Symbols/System/Library/Caches/*", .ide),
        item("JetBrains IDEs data (IntelliJ, PyCharm, WebStorm, GoLand)", "$HOME/Library/Application Support/JetBrains/*", .ide),
        item("JetBrains IDEs cache", "$HOME/Library/Caches/JetBrains/*", .ide),
        item("Android Studio cache and indexes", "$HOME/Library/Caches/Google/AndroidStudio*/*", .ide),
        item("Android build cache", "$HOME/.android/build-cache/*", .ide),
        item("VS Code runtime cache", "$HOME/Library/Application Support/Code/Cache/*", .ide),
        item("VS Code extension and update cache", "$HOME/Library/Application Support/Code/CachedData/*", .ide),
        item("VS Code system cache (Cursor, VSCodium)", "$HOME/Library/Caches/com.microsoft.VSCode/*", .ide),
        item("Cursor editor cache", "$HOME/Library/Caches/com.todesktop.230313mzl4w4u92/*", .ide),
        item("LM Studio app cache", "$HOME/Library/Caches/com.lmstudio.lmstudio/*", .aiml),
        item("Codex Desktop update staging", "$HOME/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle/Installation", .aiml),
        item("Chrome on-device AI models", "$HOME/Library/Application Support/Google/Chrome/OptGuideOnDevice*/*", .aiml),
        item("Chrome optimization guide models", "$HOME/Library/Application Support/Google/Chrome/optimization_guide_model_store/*", .aiml),
        item("Bazel build cache", "$HOME/.cache/bazel/*", .compiler),
        item("Rust Cargo registry cache", "$HOME/.cargo/registry/cache/*", .compiler),
        item("Rust documentation cache", "$HOME/.rustup/toolchains/*/share/doc/*", .compiler),
        item("Rustup toolchain downloads", "$HOME/.rustup/downloads/*", .compiler),
        item("ccache compiler cache", "$HOME/.ccache/*", .compiler),
        item("sccache distributed compiler cache", "$HOME/.cache/sccache/*", .compiler),
        item("Turbo monorepo build cache", "$HOME/.turbo/*", .compiler),
        item("Next.js build cache", "$HOME/.next/*", .compiler),
        item("Vite build cache", "$HOME/.vite/*", .compiler),
        item("Parcel bundler cache", "$HOME/.parcel-cache/*", .compiler),
        item("pre-commit hooks cache", "$HOME/.cache/pre-commit/*", .compiler),
        item("Ruff Python linter cache", "$HOME/.cache/ruff/*", .compiler),
        item("MyPy type checker cache", "$HOME/.cache/mypy/*", .compiler),
        item("Pytest test cache", "$HOME/.pytest_cache/*", .compiler),
        item("PyInstaller binary cache", "$HOME/Library/Application Support/pyinstaller/bincache*", .compiler),
        item("Flutter SDK cache", "$HOME/.cache/flutter/*", .compiler),
        item("Swift Package Manager cache", "$HOME/.cache/swift-package-manager/*", .compiler),
        item("Zig compiler cache", "$HOME/.cache/zig/*", .compiler),
        item("CocoaPods cache (iOS dependencies)", "$HOME/Library/Caches/CocoaPods/*", .packageManager),
        item("npm package cache", "$HOME/.npm/_cacache/*", .packageManager),
        item("pip Python package cache", "$HOME/.cache/pip/*", .packageManager),
        item("uv Python package cache", "$HOME/.cache/uv/*", .packageManager),
        item("R renv global cache (virtual environments)", "$HOME/Library/Caches/org.R-project.R/R/renv/*", .packageManager),
        item("tealdeer tldr pages cache", "$HOME/Library/Caches/tealdeer/tldr-pages", .packageManager),
        item("Homebrew downloaded packages", "$HOME/Library/Caches/Homebrew/*", .packageManager),
        item("Yarn package manager cache", "$HOME/.cache/yarn/*", .packageManager),
        item("pnpm package store", "$HOME/Library/pnpm/store/*", .packageManager),
        item("Composer PHP dependencies cache (legacy)", "$HOME/.composer/cache/*", .packageManager),
        item("Composer PHP dependencies cache", "$HOME/Library/Caches/composer/*", .packageManager),
        item("RubyGems cache", "$HOME/.gem/cache/*", .packageManager),
        item("Conda package metadata/tarball cache", "$HOME/.conda/pkgs", .packageManager),
        item("Anaconda package metadata/tarball cache", "$HOME/anaconda3/pkgs", .packageManager),
        item("Playwright browser binaries", "$HOME/Library/Caches/ms-playwright*", .aiml),
        item("Selenium WebDriver binaries", "$HOME/.cache/selenium/*", .aiml),
        item("Ollama local AI models", "$HOME/.ollama/models/*", .aiml),
        item("Safari web browser cache", "$HOME/Library/Caches/com.apple.Safari/*", .browser),
        item("Chrome browser cache", "$HOME/Library/Caches/Google/Chrome/*", .browser),
        item("Firefox browser cache", "$HOME/Library/Caches/Firefox/*", .browser),
        item("Brave browser cache", "$HOME/Library/Caches/BraveSoftware/Brave-Browser/*", .browser),
        item("Surge proxy cache", "$HOME/Library/Caches/com.nssurge.surge-mac/*", .network),
        item("Surge configuration and data", "$HOME/Library/Application Support/com.nssurge.surge-mac/*", .network),
        item("Docker BuildX cache", "$HOME/.docker/buildx/cache/*", .container),
        item("Podman container cache", "$HOME/.local/share/containers/cache/*", .container),
        item("Tart OCI/IPSW cache", "$HOME/.tart/cache", .container),
        item("Font cache", "$HOME/Library/Caches/com.apple.FontRegistry/*", .system, alwaysProtected: true),
        item("Spotlight metadata cache", "$HOME/Library/Caches/com.apple.spotlight/*", .system, alwaysProtected: true),
        item("CloudKit cache", "$HOME/Library/Caches/CloudKit/*", .system, alwaysProtected: true),
        item("Trash", "$HOME/.Trash", .system),
        item("iOS/iPadOS device firmware (.ipsw) from iTunes/Finder", "$HOME/Library/iTunes/*Software Updates/*.ipsw", .system),
        item("Apple Configurator 2 device firmware (.ipsw)", "$HOME/Library/Group Containers/*.group.com.apple.configurator/**/*.ipsw", .system),
        item("Finder metadata, .DS_Store", MoleConfigStore.finderMetadataSentinel, .system, alwaysProtected: true),
    ]

    private static func item(_ name: String, _ pattern: String, _ category: WhitelistCategory, alwaysProtected: Bool = false) -> WhitelistCatalogItem {
        WhitelistCatalogItem(name: name, rawPattern: pattern, category: category, isAlwaysProtected: alwaysProtected)
    }

    static var alwaysProtectedPatterns: Set<String> {
        Set(items.filter(\.isAlwaysProtected).map(\.expandedPattern))
    }

    /// What a brand-new Mole install protects before any whitelist file
    /// exists — `DEFAULT_WHITELIST_PATTERNS` in lib/core/base.sh. Used so
    /// Settings shows these as already-checked rather than nothing protected.
    static let defaultPatterns: [String] = [
        "$HOME/Library/Caches/ms-playwright*",
        "$HOME/.gradle/caches/*",
        "$HOME/.gradle/daemon/*",
        "$HOME/.ollama/models/*",
        "$HOME/Library/Caches/com.nssurge.surge-mac/*",
        "$HOME/Library/Application Support/com.nssurge.surge-mac/*",
        "$HOME/Library/Caches/org.R-project.R/R/renv/*",
        "$HOME/Library/Caches/JetBrains*",
        "$HOME/Library/Caches/com.jetbrains.toolbox*",
        "$HOME/Library/Caches/tealdeer/tldr-pages",
        "$HOME/Library/Application Support/JetBrains*",
        "$HOME/Library/Caches/com.apple.finder",
        "$HOME/Library/Mobile Documents*",
        MoleConfigStore.finderMetadataSentinel,
    ].map { $0.replacingOccurrences(of: "$HOME", with: NSHomeDirectory()) }
}
