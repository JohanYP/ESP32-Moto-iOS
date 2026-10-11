import Foundation
import CoreBluetooth
import Combine

public struct TelemetryData: Sendable {
    public var relayState: String = "OFF"
    public var zone: String = "DESCONOCIDO"
    public var rssi: String = "0.0"
    public var rxCount: String = "0"
}

@MainActor
public final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BLEManager()

    // UUIDs oficiales de ESP32 Moto
    public static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    public static let charStatusUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    public static let charLogsUUID = CBUUID(string: "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e")

    @Published public var isBluetoothPoweredOn = false
    @Published public var isScanning = false
    @Published public var isConnected = false
    @Published public var connectedPeripheralName: String = "Ninguno"
    @Published public var receiverRSSI: Int = 0
    @Published public var isReceptorAvailable: Bool = false
    @Published public var telemetry = TelemetryData()
    @Published public var logs: [String] = []

    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?

    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func startScan() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        addLog("Iniciando escaneo de 'ESP32 Moto'...")
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    public func disconnect() {
        if let p = targetPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }

    public func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        logs.append(formatted)
        if logs.count > 100 {
            logs.removeFirst()
        }
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
            if central.state == .poweredOn {
                self.addLog("Bluetooth activado. Listo para enlazar 3FA.")
                self.startScan()
            } else {
                self.addLog("Bluetooth no disponible (Estado: \(central.state.rawValue))")
                self.isConnected = false
                self.isReceptorAvailable = false
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let devName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Desconocido"
            if devName.contains("ESP32 Moto") || devName.contains("Moto") {
                self.targetPeripheral = peripheral
                self.receiverRSSI = RSSI.intValue
                self.isReceptorAvailable = true
                self.connectedPeripheralName = devName
                self.centralManager.stopScan()
                self.isScanning = false
                self.addLog("¡Receptor detectado! Conectando a \(devName) (RSSI: \(RSSI) dBm)...")
                self.centralManager.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.isReceptorAvailable = true
            self.connectedPeripheralName = peripheral.name ?? "ESP32 Moto"
            self.addLog("Enlace 3FA Bluetooth establecido con éxito.")
            peripheral.delegate = self
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.isReceptorAvailable = false
            self.addLog("Receptor desconectado. Inmovilización 3FA activada.")
            self.startScan()
        }
    }

    // MARK: - CBPeripheralDelegate

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.charStatusUUID, Self.charLogsUUID], for: service)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == Self.charStatusUUID || char.uuid == Self.charLogsUUID {
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let str = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in
            if characteristic.uuid == Self.charStatusUUID {
                self.parseStatus(str)
            } else if characteristic.uuid == Self.charLogsUUID {
                self.addLog("[RECEPTOR] \(str)")
            }
        }
    }

    private func parseStatus(_ payload: String) {
        // Formato: STATUS:<RELE>:<ZONA>:<RSSI>:<RX_COUNT>
        if payload.starts(with: "STATUS:") {
            let partes = payload.split(separator: ":")
            if partes.count >= 5 {
                telemetry.relayState = String(partes[1])
                telemetry.zone = String(partes[2])
                telemetry.rssi = String(partes[3])
                telemetry.rxCount = String(partes[4])
                isReceptorAvailable = true
            }
        }
    }
}
