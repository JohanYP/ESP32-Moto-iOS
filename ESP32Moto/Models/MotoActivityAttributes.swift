import Foundation
import ActivityKit

public struct MotoActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var isIgnitionOn: Bool
        public var distanceBle: Double
        public var distanceLora: Double
        public var isConnected: Bool
        public var isOwnerAuthenticated: Bool
        public var relayState: String
        public var statusText: String

        public init(
            isIgnitionOn: Bool = false,
            distanceBle: Double = 0.0,
            distanceLora: Double = 0.0,
            isConnected: Bool = false,
            isOwnerAuthenticated: Bool = false,
            relayState: String = "OFF",
            statusText: String = "Desconectado"
        ) {
            self.isIgnitionOn = isIgnitionOn
            self.distanceBle = distanceBle
            self.distanceLora = distanceLora
            self.isConnected = isConnected
            self.isOwnerAuthenticated = isOwnerAuthenticated
            self.relayState = relayState
            self.statusText = statusText
        }
    }

    public var motoName: String

    public init(motoName: String = "ESP32 Moto") {
        self.motoName = motoName
    }
}
