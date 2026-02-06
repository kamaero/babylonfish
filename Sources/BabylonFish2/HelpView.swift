import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🐠 BabylonFish Guide")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FeatureRow(icon: "🔀", title: "Auto-Switch", desc: "Type 'ghbdtn'? I'll turn it into 'привет'. Magic!")
                    
                    FeatureRow(icon: "✨", title: "Double Shift", desc: "Select any gibberish text and tap Shift twice. I'll try to make sense of it.")
                    
                    FeatureRow(icon: "💊", title: "Typo Fixer", desc: "I quietly fix 'teh' -> 'the' so you look professional.")
                    
                    FeatureRow(icon: "🔙", title: "Undo My Oopsie", desc: "If I fixed something I shouldn't have, hit Left Arrow (<-) immediately to revert.")
                    
                    FeatureRow(icon: "🤫", title: "Shhh Mode", desc: "Typing a password or weird code? Hit Right Arrow (->) to tell me 'Not now, fish!'")
                }
                .padding()
            }
            
            Text("Made for fingers that move faster than brains. 🧠💨")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom)
        }
        .frame(width: 450, height: 500)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(icon)
                .font(.system(size: 30))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
