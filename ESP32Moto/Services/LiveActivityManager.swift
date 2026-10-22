import Foundation
import ActivityKit

@MainActor
public final class LiveActivityManager: ObservableObject {
    public static let shared = LiveActivityManager()

    @Published public var currentActivity: Activity<MotoActivityAttributes>? = nil

    private init() {
        // Enlazar con actividad existente si ya hay una corriendo
        if #available(iOS 16.1, *) {
            currentActivity = Activity<MotoActivityAttributes>.activities.first
        }
    }

    public func startLiveActivity(initialState: MotoActivityAttributes.ContentState) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Si ya hay una actividad corriendo, simplemente actualizarla
        if let existing = Activity<MotoActivityAttributes>.activities.first {
            currentActivity = existing
            updateLiveActivity(state: initialState)
            return
        }

        let attributes = MotoActivityAttributes(motoName: "ESP32 Moto")
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity<MotoActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
        } catch {
            print("[LiveActivity] Error al iniciar actividad: \(error.localizedDescription)")
        }
    }

    public func updateLiveActivity(state: MotoActivityAttributes.ContentState) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = currentActivity ?? Activity<MotoActivityAttributes>.activities.first else {
            startLiveActivity(initialState: state)
            return
        }

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    public func endLiveActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = currentActivity ?? Activity<MotoActivityAttributes>.activities.first else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
    }
}
