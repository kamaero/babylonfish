import CreateML
import Foundation

// 1. Load Data
let csvFile = URL(fileURLWithPath: "ML/Data/sample_dataset.csv")
do {
    let data = try MLDataTable(contentsOf: csvFile)
    
    // 2. Split Data
    let (trainingData, testingData) = data.randomSplit(by: 0.8, seed: 5)
    
    // 3. Train Model
    // We use a Maximum Entropy classifier for text
    let classifier = try MLTextClassifier(trainingData: trainingData, textColumn: "text", labelColumn: "label")
    
    // 4. Evaluate
    let evaluation = classifier.evaluation(on: testingData, textColumn: "text", labelColumn: "label")
    let accuracy = (1.0 - evaluation.classificationError) * 100
    print("Training Accuracy: \(accuracy)%")
    
    // 5. Metadata
    let metadata = MLModelMetadata(author: "BabylonFish Team",
                                   shortDescription: "Detects EN, RU and RU_WRONG (gibberish)",
                                   version: "1.0")
    
    // 6. Save Model
    let outputPath = URL(fileURLWithPath: "ML/Models/BabylonFishClassifier.mlmodel")
    try classifier.write(to: outputPath, metadata: metadata)
    print("Model saved to: \(outputPath.path)")
    
} catch {
    print("Error: \(error)")
    exit(1)
}
