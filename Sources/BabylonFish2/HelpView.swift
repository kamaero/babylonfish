import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🐠 BabylonFish Инструкция")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FeatureRow(icon: "🔀", title: "Авто-переключение", desc: "Печатаете 'ghbdtn'? Я превращу это в 'привет'. Магия!")
                    
                    FeatureRow(icon: "✨", title: "Двойной Shift", desc: "Выделите любую абракадабру и нажмите Shift дважды. Я постараюсь это исправить.")
                    
                    FeatureRow(icon: "💊", title: "Исправление опечаток", desc: "Я тихо исправляю 'поже' -> 'позже', чтобы вы выглядели профессионально.")
                    
                    FeatureRow(icon: "🔙", title: "Отмена исправления", desc: "Если я исправил зря, нажмите Стрелку Влево (<-) сразу же, чтобы вернуть как было.")
                    
                    FeatureRow(icon: "🤫", title: "Тихий режим", desc: "Вводите пароль или код? Нажмите Стрелку Вправо (->), чтобы сказать мне 'Не сейчас, рыбка!'")
                }
                .padding()
            }
            
            Text("Сделано для пальцев, которые быстрее мыслей. 🧠💨")
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
