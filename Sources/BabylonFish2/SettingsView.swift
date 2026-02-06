import SwiftUI

struct SettingsView: View {
    @State private var config = AppConfig.load()
    @State private var startAtLogin = false
    @State private var newException = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Включить авто-переключение", isOn: $config.exceptions.globalEnabled)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: config.exceptions.globalEnabled) {
                    config.save()
                    notifyEngineConfigChanged()
                }
            
            Toggle("Авто-исправление опечаток", isOn: $config.exceptions.autoCorrectTypos)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: config.exceptions.autoCorrectTypos) {
                    config.save()
                    notifyEngineConfigChanged()
                }
            
            Toggle("Запускать при входе", isOn: $startAtLogin)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: startAtLogin) { _, newValue in
                    LaunchAgentManager.toggle(newValue)
                    UserDefaults.standard.set(newValue, forKey: "startAtLoginPreferred")
                }
                .padding(.bottom)
            
            Text("Исключения (Приложения или Слова):")
                .font(.headline)
            
            HStack {
                TextField("Добавить исключение...", text: $newException)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Добавить") {
                    if !newException.isEmpty {
                        config.exceptions.wordExceptions.insert(newException)
                        config.save()
                        newException = ""
                        notifyEngineConfigChanged()
                    }
                }
            }
            
            List {
                ForEach(Array(config.exceptions.wordExceptions.sorted()), id: \.self) { item in
                    Text(item)
                }
                .onDelete(perform: deleteException)
            }
            .border(Color.gray.opacity(0.2))
            
            Text("Примечание: Нажмите Стрелку Вправо (->) для временной отмены переключения.")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top)
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            startAtLogin = LaunchAgentManager.isEnabled()
        }
    }
    
    func deleteException(at offsets: IndexSet) {
        let sortedItems = Array(config.exceptions.wordExceptions.sorted())
        for offset in offsets {
            if offset < sortedItems.count {
                config.exceptions.wordExceptions.remove(sortedItems[offset])
            }
        }
        config.save()
        notifyEngineConfigChanged()
    }
    
    private func notifyEngineConfigChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("BabylonFishConfigChanged"), object: nil)
    }
}
