import Foundation

// Simple test to verify contextual analysis works
func testContextualAnalysis() {
    print("=== Testing Contextual Analysis ===")
    
    // Create a minimal test
    let analyzer = ContextAnalyzer()
    
    // Test 1: Basic analysis
    print("Test 1: Analyzing 'function' in IDE context")
    let context1 = DetectionContext(
        applicationType: .ide,
        isSecureField: false,
        previousWords: nil,
        userPreferences: nil
    )
    let result1 = analyzer.analyzeContext(for: "function", externalContext: context1)
    print("  Result: \(result1.description)")
    
    // Test 2: Update context and analyze again
    print("\nTest 2: Updating context with Russian words")
    analyzer.updateContext(text: "привет", language: .russian)
    analyzer.updateContext(text: "как", language: .russian)
    
    let currentContext = analyzer.getCurrentContext()
    print("  Current context: \(currentContext.description)")
    
    // Test 3: Analyze ambiguous word with Russian context
    print("\nTest 3: Analyzing 'rfr' with Russian context")
    let result3 = analyzer.analyzeContext(for: "rfr")
    print("  Result: \(result3.description)")
    
    // Test 4: Clear context and test English
    print("\nTest 4: Clearing context and testing English")
    analyzer.clearContext()
    analyzer.updateContext(text: "hello", language: .english)
    analyzer.updateContext(text: "world", language: .english)
    
    let result4 = analyzer.analyzeContext(for: "руддщ")
    print("  Result: \(result4.description)")
    
    print("\n=== Test Complete ===")
}

// Run the test
testContextualAnalysis()