# BabylonFish - Agent Guidelines

This document provides guidelines for AI agents working on BabylonFish - a macOS keyboard layout auto-switching application.

## Project Overview

BabylonFish automatically detects and switches keyboard layouts when users type in the wrong language. Features:
- Automatic layout switching (e.g., "ghbdtn" → "привет")
- Double Shift shortcut for manual correction
- Context-aware processing (ignores password fields)
- Typo correction and auto-completion (v3)

## Build Commands

### Development Build
```bash
# Build BabylonFish2 (legacy)
swift build --product BabylonFish2

# Build BabylonFish3 (current)
swift build --product BabylonFish3

# Build for specific architecture
swift build -c debug --product BabylonFish3 --arch arm64
swift build -c debug --product BabylonFish3 --arch x86_64
```

### Release Build
```bash
# Build and install universal binary
./install_app.sh

# Manual build for both architectures
swift build -c release --product BabylonFish3 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish3 --disable-sandbox

# Create universal binary
lipo -create -output "BabylonFish" \
  ".build/arm64-apple-macosx/release/BabylonFish3" \
  ".build/x86_64-apple-macosx/release/BabylonFish3"
```

### Package Management
```bash
# Update dependencies
swift package update

# Clean build
rm -rf .build
```

## Testing Commands

### Manual Testing
```bash
# Run the application
./run_app.sh
# Or directly
open ~/Applications/BabylonFish.app

# Check debug logs
tail -f ~/babylonfish_debug.log
# Clear debug logs
> ~/babylonfish_debug.log
```

### Test Scripts
```bash
# Run BabylonFish3 test suite
./test_babylonfish3.sh

# Test contextual processing
swift test_contextual.swift
```

### Testing Scenarios
1. **Simple word detection**: Type "ghbdtn" (English) → "привет" (Russian)
2. **Short word detection**: Type "rfr" → "как"
3. **Double Shift**: Select text, double-tap Left Shift
4. **Context awareness**: Should ignore password fields
5. **Typo correction**: "havv" → "have" (v3 only)
6. **Auto-completion**: Partial words (v3 only)

### Debug Log Analysis
Check `~/babylonfish_debug.log` for:
- `Event received: type=10` - Events captured
- `Language detected:` - Language detection working
- `Switching layout to...` - Layout switching attempted
- `Found matching source:` - Layout source found
- `Context check:` - Context analysis results

## Code Style Guidelines

### File Organization
```
Sources/BabylonFish2/
├── Core/           # Core engine components
├── Language/       # Language detection and processing
├── Configuration/  # App configuration and state
├── UI/            # User interface components
└── Utils/         # Utility classes and helpers
```

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `EventProcessor`, `LanguageDetector`)
- **Structs**: `PascalCase` (e.g., `AppConfig`, `KeyCombo`)
- **Enums**: `PascalCase` with cases in `camelCase` (e.g., `Language.english`, `Language.russian`)
- **Variables**: `camelCase` (e.g., `currentBuffer`, `isEnabled`)
- **Constants**: `camelCase` or `UPPER_SNAKE_CASE` for global constants
- **Functions**: `camelCase` (e.g., `detectLanguage()`, `switchLayout()`)

### Import Order
```swift
// 1. Foundation and system frameworks
import Foundation
import Cocoa
import Carbon

// 2. Third-party dependencies (none currently)

// 3. Local modules (if any)
```

### Type Annotations
- Always specify return types for functions
- Use explicit type annotations for public API
- Prefer `let` over `var` for immutable values
- Use optionals appropriately with `?` and `!` only when safe

### Error Handling
```swift
// Use do-catch for recoverable errors
do {
    try someOperation()
} catch {
    logDebug("Error: \(error)")
}

// Use optional binding for expected failures
guard let result = try? operation() else {
    return
}

// Log errors to debug log
logDebug("Error description")
```

### Logging
- Use `logDebug()` function for all debug logging
- Logs go to `~/babylonfish_debug.log`
- Include timestamps and context in log messages
- Use descriptive messages that help with debugging

### Swift Conventions
- Use Swift's modern concurrency (`async/await`) when appropriate
- Prefer value types (structs) over reference types (classes) when possible
- Use protocols for abstraction
- Follow Swift API Design Guidelines

### Memory Management
- Use `weak` references for delegates to avoid retain cycles
- Properly handle `Unmanaged` types when working with Core Foundation
- Clean up resources in `deinit` when necessary

## Architecture Notes

### Event Processing Flow
```
CGEvent → EventTapManager → EventProcessor → BufferManager
                                      ↓
                            ContextAnalyzer (context check)
                                      ↓
                            LanguageDetector (language detection)
                                      ↓
                            LayoutSwitcher (switch + retype)
```

### Configuration
- Use `AppConfig` struct for Codable configuration
- Migrate from UserDefaults to structured config
- Support backward compatibility for user settings

### Performance Requirements
- Event processing must be fast (< 1ms)
- Language detection should be efficient
- Memory usage should be minimal
- Avoid blocking the main thread

### Security Requirements
- Never log sensitive information (passwords, etc.)
- Respect privacy - don't send data externally
- Handle permissions appropriately
- Validate all inputs and configurations

## Agent Operations

### Before Making Changes
1. **Always run tests**: Use `./test_babylonfish3.sh` or manual testing
2. **Check logs**: Verify `~/babylonfish_debug.log` for errors
3. **Build verification**: Run `./install_app.sh` to ensure build works

### Code Quality Checks
- **No linting tools**: This project doesn't use SwiftLint or other linters
- **Manual verification**: Check code follows existing patterns
- **Performance**: Event processing must remain under 1ms

### Testing Requirements
- **Unit tests**: Not currently implemented; focus on manual testing
- **Integration tests**: Use `test_contextual.swift` for contextual processing
- **Manual testing**: Always test typing scenarios before committing

### Common Pitfalls
1. **Permissions**: App needs Accessibility + Input Monitoring permissions
2. **Event capture**: Verify events are received in debug logs
3. **Layout switching**: Ensure Russian/English layouts are installed
4. **Memory leaks**: Check for retain cycles in delegates

### Quick Reference
```bash
# Build and test
./install_app.sh
./test_babylonfish3.sh
tail -f ~/babylonfish_debug.log

# Reset if needed
tccutil reset Accessibility com.babylonfish.app
> ~/babylonfish_debug.log
```