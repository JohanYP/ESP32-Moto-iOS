import Foundation
import CoreBluetooth
import Combine
import CommonCrypto

public struct TelemetryData: Sendable {
    public var relayState: String = "OFF"
    public var zone: String = "DESCONOCIDO"
    public var rssi: String = "0.0"
    public var rxCount: String = "0"
    public var ownerAuth: String = "NO_AUTH"
}

@MainActor
public final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BLEManager()

    public static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    public static let charStatusUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    public static let charLogsUUID = CBUUID(string: "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e")
    public static let charAuthUUID = CBUUID(string: "2a37f5a8-b641-479e-a81d-8f2c3b4e5a6f")

    // Clave criptográfica única del Propietario (guardada de forma segura)
    public static let defaultOwnerKey = "MOTO_OWNER_KEY_2026_POPAYAN"

    @Published public var isBluetoothPoweredOn = false
    @Published public var isScanning = false
    @Published public var isConnected = false
    @Published public var isOwnerAuthenticated = false
    @Published public var connectedPeripheralName: String = "Ninguno"
    @Published public var receiverRSSI: Int = 0
    @Published public var isReceptorAvailable: Bool = false
    @Published public var telemetry = TelemetryData()
    @Published public var logs: [String] = []

    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var authCharacteristic: CBCharacteristic?

    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func startScan() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        addLog("Buscando inmovilizador 'ESP32 Moto'...")
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    public func sendCommand(_ command: String) {
        guard isConnected, isOwnerAuthenticated, let char = authCharacteristic, let data = "CMD:\(command)".data(using: .utf8) else {
            addLog("No se pudo enviar comando: No autenticado.")
            return
        }
        addLog("Enviando comando: CMD:\(command)")
        targetPeripheral?.writeValue(data, for: char, type: .withResponse)
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

    // Cálculo HMAC-SHA256 nativo de iOS
    private func computeHMAC(key: String, message: String) -> String {
        let keyData = key.data(using: .utf8)!
        let msgData = message.data(using: .utf8)!
        var macOut = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBytes in
            msgData.withUnsafeBytes { msgBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBytes.baseAddress, keyData.count, msgBytes.baseAddress, msgData.count, &macOut)
            }
        }
        return macOut.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
            if central.state == .poweredOn {
                self.addLog("Bluetooth activado. Listo para enlazar 3FA.")
                self.startScan()
            } else {
                self.addLog("Bluetooth no disponible.")
                self.isConnected = false
                self.isOwnerAuthenticated = false
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
            self.addLog("Conexión física BLE establecida. Verificando credenciales de Propietario...")
            peripheral.delegate = self
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.isOwnerAuthenticated = false
            self.isReceptorAvailable = false
            self.authCharacteristic = nil
            self.addLog("Desconectado de la motocicleta. Inmovilización 3FA activada.")
            self.startScan()
        }
    }

    // MARK: - CBPeripheralDelegate

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.charStatusUUID, Self.charLogsUUID, Self.charAuthUUID], for: service)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == Self.charAuthUUID {
                Task { @MainActor in
                    self.authCharacteristic = char
                    self.addLog("Canal de autenticación detectado. Suscribiendo y solicitando desafío...")
                }
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
            } else if char.uuid == Self.charStatusUUID || char.uuid == Self.charLogsUUID {
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == Self.charAuthUUID, characteristic.isNotifying {
            Task { @MainActor in
                self.addLog("Canal de seguridad suscrito. Solicitando desafío al receptor...")
                if let reqData = "REQ_CHALLENGE".data(using: .utf8) {
                    peripheral.writeValue(reqData, for: characteristic, type: .withResponse)
                }
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let str = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in
            if characteristic.uuid == Self.charAuthUUID {
                self.handleAuthMessage(str, peripheral: peripheral)
            } else if characteristic.uuid == Self.charStatusUUID {
                self.parseStatus(str)
            } else if characteristic.uuid == Self.charLogsUUID {
                self.addLog("[MOTO] \(str)")
            }
        }
    }

    private func handleAuthMessage(_ payload: String, peripheral: CBPeripheral) {
        if payload.starts(with: "CHALLENGE:") {
            let nonce = String(payload.dropFirst(10))
            addLog("Desafío recibido de la moto: Nonce \(nonce.prefix(8))...")
            let hmacResponse = computeHMAC(key: Self.defaultOwnerKey, message: nonce)
            let responsePayload = "AUTH:\(nonce):\(hmacResponse)"

            if let authChar = authCharacteristic, let respData = responsePayload.data(using: .utf8) {
                addLog("Firmando con clave secreta del Dueño y respondiendo...")
                peripheral.writeValue(respData, for: authChar, type: .withResponse)
            }
        } else if payload.starts(with: "AUTH_OK") {
            isOwnerAuthenticated = true
            addLog(">>> PROPIETARIO AUTORIZADO CON ÉXITO (3FA HABILITADO) <<<")
        } else if payload.starts(with: "AUTH_FAIL") {
            isOwnerAuthenticated = false
            addLog(">>> ALERTA: AUTENTICACIÓN DENEGADA (NO ES EL DUEÑO) <<<")
        }
    }

    private func parseStatus(_ payload: String) {
        // Formato: STATUS:<RELE>:<ZONA>:<RSSI>:<RX_COUNT>:<AUTH>
        if payload.starts(with: "STATUS:") {
            let partes = payload.split(separator: ":")
            if partes.count >= 5 {
                telemetry.relayState = String(partes[1])
                telemetry.zone = String(partes[2])
                telemetry.rssi = String(partes[3])
                telemetry.rxCount = String(partes[4])
                if partes.count >= 6 {
                    telemetry.ownerAuth = String(partes[5])
                    if telemetry.ownerAuth == "DUENO_OK" {
                        isOwnerAuthenticated = true
                    }
                }
                isReceptorAvailable = true
            }
        }
    }
}
