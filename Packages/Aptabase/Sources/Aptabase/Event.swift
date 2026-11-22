import Foundation

public struct Event: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var sessionId: String
    public var eventName: String
    public var systemProps: SystemProps
    public var props: [String: AnyCodableValue]?

    public init(
        timestamp: Date,
        sessionId: String,
        eventName: String,
        systemProps: SystemProps,
        props: [String: AnyCodableValue]? = nil
    ) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.eventName = eventName
        self.systemProps = systemProps
        self.props = props
    }

    public struct SystemProps: Codable, Sendable, Equatable {
        public var isDebug: Bool
        public var locale: String
        public var osName: String
        public var osVersion: String
        public var appVersion: String
        public var appBuildNumber: String
        public var sdkVersion: String
        public var deviceModel: String

        public init(
            isDebug: Bool,
            locale: String,
            osName: String,
            osVersion: String,
            appVersion: String,
            appBuildNumber: String,
            sdkVersion: String,
            deviceModel: String
        ) {
            self.isDebug = isDebug
            self.locale = locale
            self.osName = osName
            self.osVersion = osVersion
            self.appVersion = appVersion
            self.appBuildNumber = appBuildNumber
            self.sdkVersion = sdkVersion
            self.deviceModel = deviceModel
        }
    }
}
