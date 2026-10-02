#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/test-module-cache
xcrun swiftc -swift-version 5 -module-cache-path build/test-module-cache Sources/Model.swift Tests/main.swift -o build/lanes-tests
build/lanes-tests

xcrun swiftc -swift-version 5 -module-cache-path build/test-module-cache Sources/Model.swift Sources/NativeResizeGrip.swift Tests/NativeGripTests.swift -o build/native-grip-tests -framework AppKit -framework SwiftUI
build/native-grip-tests

xcrun swiftc -swift-version 5 -module-cache-path build/test-module-cache Sources/Model.swift Sources/WindowManager.swift Tests/AppDiscoveryTests.swift -o build/app-discovery-tests -framework AppKit -framework ApplicationServices
build/app-discovery-tests

xcrun swiftc -swift-version 5 -module-cache-path build/test-module-cache Sources/Model.swift Sources/HoverScrollView.swift Tests/NativeHoverTests.swift -o build/native-hover-tests -framework AppKit -framework SwiftUI
build/native-hover-tests
