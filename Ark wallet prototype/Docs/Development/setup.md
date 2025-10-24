# Development Environment Setup

This guide walks through setting up your development environment for the Arké Wallet prototype.

## Prerequisites

### System Requirements
- **macOS**: 14.0 or later (Sonoma)
- **Xcode**: 15.0 or later
- **Swift**: 5.9 or later (included with Xcode)
- **Command Line Tools**: Xcode Command Line Tools installed

### External Dependencies
- **Bark CLI**: Version 0.0.0-alpha.20 or compatible
  - Used for wallet operations and testing
  - Must be accessible in your PATH or configured in the app

## Initial Setup

### 1. Clone and Build

```bash
# Clone the repository
git clone [repository-url]
cd ark-wallet-prototype

# Open in Xcode
open Ark-wallet-prototype.xcodeproj
```

### 2. Xcode Configuration

**Build Settings to Verify**:
- Deployment Target: macOS 14.0
- Swift Language Version: Swift 5
- Code Signing: Development team configured

**Scheme Configuration**:
- Run scheme should target your Mac
- Enable SwiftUI Preview support
- Configure debug/release builds as needed

### 3. Bark CLI Setup

**Installation** (development version):
```bash
# Install or build Bark CLI tool
# Ensure it's in your PATH or note the full path
which bark  # Should return the path to bark executable
```

**Configuration for Development**:
- The app can run in preview mode without Bark CLI
- For full functionality, configure Bark CLI path in app settings
- Use signet network for testing (never mainnet)

## Project Structure

### Key Directories
```
Ark-wallet-prototype/
├── Views/                 # SwiftUI views and UI components
├── Services/             # Business logic and wallet operations
├── Models/               # Data models and persistence
├── Protocols/            # Abstract interfaces (BarkWalletProtocol, etc.)
├── Utils/                # Utility classes and extensions
├── Preview Content/      # Assets and mock data for SwiftUI previews
└── Tests/               # Unit and UI tests
```

### Important Files
- **`Ark_wallet_prototypeApp.swift`**: Main app entry point and SwiftData configuration
- **`WalletManager.swift`**: Central coordinator for all wallet operations
- **`BarkWallet.swift`**: Concrete wallet implementation using Bark CLI
- **`MockBarkWallet.swift`**: Mock implementation for testing and previews

## Development Workflows

### SwiftUI Previews
The app is designed to work well with SwiftUI previews:

```swift
#Preview {
    ContentView()
        .environment(WalletManager.shared)  // Uses mock data
}
```

**Preview Configuration**:
- All services have mock implementations
- Preview data is realistic but safe
- No external dependencies required

### Running the App

**Development Mode**:
1. Build and run from Xcode
2. App starts with mock data if Bark CLI not configured
3. Configure real Bark CLI path in settings for full functionality

**Testing Mode**:
- Use signet network only
- Never test with real Bitcoin
- Clear wallet data between test sessions

### Debugging

**Logging**:
- Services use print statements with prefixes (❌ for errors, ✅ for success)
- SwiftData operations are logged for debugging persistence issues
- Bark CLI interactions are logged with request/response data

**Common Debug Points**:
- Service initialization and dependency injection
- SwiftData persistence and cache invalidation
- Async operation completion and error handling
- UI state updates and SwiftUI observation

## Development Best Practices

### Code Organization
- Keep services focused on single responsibilities
- Use dependency injection for testability
- Implement protocol-based abstractions
- Follow Swift API design guidelines

### SwiftUI Patterns
- Use `@Observable` for service classes
- Prefer SwiftUI observation over manual state management
- Design views to work with both real and mock data
- Use SwiftUI previews extensively during development

### Testing Strategy
- Write tests for business logic in services
- Use mock implementations for external dependencies
- Test UI components with SwiftUI preview data
- Include error scenarios in test cases

### Performance Considerations
- Use task deduplication to prevent redundant operations
- Implement appropriate caching strategies
- Test with realistic data sizes
- Profile memory usage with large transaction histories

## Common Issues and Solutions

### Bark CLI Integration
**Issue**: App can't find Bark CLI
**Solution**: 
- Verify Bark CLI is installed and in PATH
- Configure absolute path in app settings
- Check file permissions

### SwiftData Persistence
**Issue**: Data not persisting between launches
**Solution**:
- Verify ModelContainer configuration in app file
- Check model definitions use @Model correctly
- Clear corrupt data files if necessary

### Preview Issues
**Issue**: Previews not working or showing errors
**Solution**:
- Ensure mock data is properly configured
- Check that preview uses mock implementations
- Restart Xcode if previews are stuck

### Performance Problems
**Issue**: App feels slow or unresponsive
**Solution**:
- Check for blocking operations on main thread
- Verify async operations are properly implemented
- Review caching strategy and cache hit rates

## Next Steps

After completing this setup:
1. Review the [Testing Patterns](testing-patterns.md) documentation
2. Familiarize yourself with [Common Tasks](common-tasks.md)
3. Read the architectural documentation for system understanding
4. Start with small changes to understand the codebase

## Getting Help

### Resources
- Architectural documentation for system design
- API reference for service interfaces
- Swift and SwiftUI documentation
- Ark protocol documentation

### Contributing
- Start by running tests to ensure everything works
- Make small, focused changes
- Follow existing patterns and conventions
- Test thoroughly before submitting changes

---

*Note: This setup guide should be updated as the development environment evolves.*