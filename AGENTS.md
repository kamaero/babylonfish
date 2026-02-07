# BabylonFish - Agent Guidelines

This document provides guidelines for AI agents working on the BabylonFish project - a macOS keyboard layout auto-switching application.

## Project Overview

BabylonFish is a macOS application that automatically detects and switches keyboard layouts when users type in the wrong language. It features:
- Automatic layout switching (e.g., "ghbdtn" → "привет")
- Double Shift shortcut for manual correction
- System spell checker integration
- Context-aware processing (ignores password fields, etc.)

## Build Commands

### Development Build
```bash
# Build for development (debug mode)
swift build --product BabylonFish2

# Build for specific architecture
swift build -c debug --product BabylonFish2 --arch arm64
swift build -c debug --product BabylonFish2 --arch x86_64
```

### Release Build
```bash
# Build universal binary (both architectures)
./install_app.sh

# Or manually:
swift build -c release --product BabylonFish2 --disable-sandbox
arch -x86_64 swift build -c release --product BabylonFish2 --disable-sandbox

# Create universal binary
lipo -create -output "BabylonFish" \
  ".build/arm64-apple-macosx/release/BabylonFish2" \
  ".build/x86_64-apple-macosx/release/BabylonFish2"
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
cat ~/babylonfish_debug.log

# Clear debug logs
> ~/babylonfish_debug.log
```

### Testing Scenarios
1. **Simple word detection**: Type "ghbdtn" in English layout → should switch to Russian "привет"
2. **Short word detection**: Type "rfr" → should switch to "как"
3. **Double Shift**: Type text, select it, double-tap Left Shift
4. **Context awareness**: Should ignore password fields

### Debug Log Analysis
Check `~/babylonfish_debug.log` for:
- `Event received: type=10` - Events are being captured
- `Language detected:` - Language detection is working
- `Switching layout to...` - Layout switching is attempted
- `Found matching source:` - Layout source is found

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

## Architecture Guidelines

### Core Principles
1. **Modularity**: Keep components focused and single-responsibility
2. **Testability**: Design for unit testing where possible
3. **Performance**: Optimize critical paths (event processing, layout switching)
4. **Reliability**: Handle edge cases and errors gracefully

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

## Development Workflow

### Before Committing
1. Run the application and test basic functionality
2. Check debug logs for any errors
3. Ensure the build script works: `./install_app.sh`
4. Test on both Intel and Apple Silicon if possible

### Common Issues
1. **Permissions**: Application needs Accessibility and Input Monitoring permissions
2. **Layout detection**: Ensure Russian and English layouts are installed
3. **Event capture**: Check if events are being received in debug logs

### Debugging Tips
- Use `tccutil reset Accessibility com.babylonfish.app` to reset permissions
- Check available layouts with Carbon API
- Monitor `~/babylonfish_debug.log` for detailed execution flow

## Project Structure Notes

- **Package.swift**: Swift Package Manager configuration
- **Sources/BabylonFish2/**: Main source code
- **dist/**: Built application bundles
- **releases/**: Versioned releases
- **Scripts**: Various shell scripts for building and deployment

## Testing Strategy

### Unit Testing
- Focus on core logic (LanguageDetector, BufferManager, etc.)
- Mock dependencies for isolation
- Test edge cases and error conditions

### Integration Testing
- Test event processing pipeline
- Verify layout switching works correctly
- Test configuration loading and migration

### Manual Testing
- Test with real keyboard input
- Verify permissions work correctly
- Test in different applications (TextEdit, Terminal, browsers)

## Performance Considerations

- Event processing must be fast (< 1ms)
- Language detection should be efficient
- Memory usage should be minimal
- Avoid blocking the main thread

## Security Considerations

- Never log sensitive information (passwords, etc.)
- Respect privacy - don't send data externally
- Handle permissions appropriately
- Validate all inputs and configurations

## Documentation

- Keep README.md up to date
- Update TESTING.md with new testing procedures
- Maintain ARCHITECTURE_V2.md for architectural decisions
- Add code comments for complex logic

## Release Process

1. Update version in Info.plist
2. Run `./install_app.sh` to build and install
3. Test the new version thoroughly
4. Create release package if needed
5. Update documentation if features change