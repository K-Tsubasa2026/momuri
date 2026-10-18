import SwiftUI
import RiveRuntime

/// Rive로 만든 모무리 캐릭터 (Assets/Momuri/rive → momuri.riv).
/// 상태는 view model 숫자 `mood` 하나로 바꾼다. 원본 생성기: Assets/Momuri/tools/make_rive.py
struct MomuriCharacterView: View {
    enum Mood: Double {
        case idle = 0, hop, cheer, wonder, sleepy
    }

    let mood: Mood
    @StateObject private var model = MomuriRiveModel()

    var body: some View {
        model.view()
            .onAppear { model.set(mood) }
            .onChange(of: mood) { _, new in model.set(new) }
    }
}

final class MomuriRiveModel: RiveViewModel {
    // 상태 머신에 묶인 인스턴스를 잡고 있어야 값을 바꿀 수 있다
    private var instance: RiveDataBindingViewModel.Instance?
    private var pending: MomuriCharacterView.Mood = .idle

    init() {
        super.init(fileName: "momuri", stateMachineName: "Momuri", fit: .contain, autoPlay: true)
        riveModel?.enableAutoBind { [weak self] instance in
            guard let self else { return }
            self.instance = instance
            instance.numberProperty(fromPath: "mood")?.value = Float(pending.rawValue)
        }
    }

    func set(_ mood: MomuriCharacterView.Mood) {
        pending = mood
        instance?.numberProperty(fromPath: "mood")?.value = Float(mood.rawValue)
    }
}
