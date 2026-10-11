import Foundation
import CoreBluetooth
import Combine
import CommonCrypto

public struct TelemetryData: Sendable {
    public var relayState: String = "OFF"
    public var zone: String = "DESCONOCIDO"
    public var rssiLora: String = "0.0"
    public var rxCount: String = "0"
    public var ownerAuth: String = "NO_AUTH"
    public var distanceLoraMeters: Double = 0.0
    public var distanceBleMeters: Double = 0.0
}

@MainActor
public final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static let shared = BLEManager()

    public static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    public static let charStatusUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    public static let charLogsUUID = CBUUID(string: "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e")
    public static let charAuthUUID = CBUUID(string: "2a37f5a8-b641-479e-a81d-8f2c3b4e5a6f")

    private static let keyStorageKey = "saved_moto_owner_key_v1"

    @Published public var isBluetoothPoweredOn = false
    @Published public var isScanning = false
    @Published public var isConnected = false
    @Published public var isOwnerAuthenticated = false
    @Published public var isProvisioned = false
    @Published public var provisioningError: String? = nil
    @Published public var pinBlockedSeconds: Int = 0
    @Published public var isResetRequested: Bool = false

    @Published public var connectedPeripheralName: String = "ESP32 Moto"
    @Published public var receiverRSSI: Int = 0
    @Published public var isReceptorAvailable: Bool = false
    @Published public var telemetry = TelemetryData()
    @Published public var logs: [String] = []

    private var currentOwnerKey: String = ""
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var authCharacteristic: CBCharacteristic?

    override private init() {
        super.init()
        if let savedKey = UserDefaults.standard.string(forKey: Self.keyStorageKey), !savedKey.isEmpty {
            self.currentOwnerKey = savedKey
            self.isProvisioned = true
        } else {
            self.isProvisioned = false
        }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func provisionWithPin(_ pin: String) {
        guard isConnected, let char = authCharacteristic else {
            provisioningError = "No hay conexión Bluetooth con la motocicleta."
            return
        }
        provisioningError = nil
        addLog("Enviando PIN maestro para aprovisionamiento...")
        let payload = "PROVISION:\(pin)"
        if let data = payload.data(using: .utf8) {
            targetPeripheral?.writeValue(data, for: char, type: .withResponse)
        }
    }

    public func resetLocalProvisioning() {
        UserDefaults.standard.removeObject(forKey: Self.keyStorageKey)
        currentOwnerKey = ""
        isProvisioned = false
        isOwnerAuthenticated = false
        addLog("Aprovisionamiento local borrado. Listo para nuevo PIN.")
    }

    public func startScan() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        addLog("Buscando inmovilizador 'ESP32 Moto'...")
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    public func disconnect() {
        if let p = targetPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }

    public func sendCommand(_ command: String) {
        guard isConnected, isOwnerAuthenticated, let char = authCharacteristic, let data = "CMD:\(command)".data(using: .utf8) else {
            addLog("Comando no enviado: No autenticado.")
            return
        }
        addLog("Enviando orden a la moto: CMD:\(command)")
        targetPeripheral?.writeValue(data, for: char, type: .withResponse)
    }

    public func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        logs.append(formatted)
        if logs.count > 120 {
            logs.removeFirst()
        }
    }

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

    private func computeBleDistance(rssi: Int) -> Double {
        if rssi >= 0 || rssi < -100 { return 0.0 }
        if rssi > -40 { return 0.25 }
        let d = pow(10.0, Double(-58 - rssi) / (10.0 * 2.0))
        return min(max(d, 0.2), 25.0)
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
            if central.state == .poweredOn {
                self.addLog("Bluetooth activado. Iniciando búsqueda...")
                self.startScan()
            } else {
                self.addLog("Bluetooth desactivado.")
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
                self.telemetry.distanceBleMeters = self.computeBleDistance(rssi: RSSI.intValue)
                self.isReceptorAvailable = true
                self.connectedPeripheralName = devName
                self.centralManager.stopScan()
                self.isScanning = false
                self.addLog("Receptor detectado (RSSI: \(RSSI) dBm). Conectando...")
                self.centralManager.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.isReceptorAvailable = true
            self.connectedPeripheralName = peripheral.name ?? "ESP32 Moto"
            self.addLog("Enlace BLE establecido. Solicitando servicios...")
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
            self.addLog("Desconectado de la moto. Inmovilización 3FA activada.")
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
                if self.isProvisioned {
                    self.addLog("Canal suscrito. Solicitando desafío criptográfico...")
                    if let reqData = "REQ_CHALLENGE".data(using: .utf8) {
                        peripheral.writeValue(reqData, for: characteristic, type: .withResponse)
                    }
                } else {
                    self.addLog("Dispositivo no aprovisionado. Requiere PIN maestro para vincular.")
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

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            self.receiverRSSI = RSSI.intValue
            self.telemetry.distanceBleMeters = self.computeBleDistance(rssi: RSSI.intValue)
        }
    }

    private func handleAuthMessage(_ payload: String, peripheral: CBPeripheral) {
        // CASO 0: SOLICITUD DE RESETEO POR BOTÓN FÍSICO (LLAVERO / MOTO)
        if payload.starts(with: "RESET_PENDING") {
            self.isResetRequested = true
            addLog(">>> ALERTA FÍSICA: Se presionó el botón físico para reiniciar el PIN. Esperando confirmación Face ID... <<<")
            return
        }

        if payload == "RESET_EXPIRED" || payload.contains("RESET_CANCELADO") {
            self.isResetRequested = false
            addLog("Solicitud de reinicio de PIN cancelada o expirada.")
            return
        }

        if payload.contains("RESET_CONFIRMADO") {
            self.isResetRequested = false
            resetLocalProvisioning()
            addLog(">>> RESTABLECIMIENTO CONFIRMADO CON FACE ID: PIN maestro restaurado a 123456. <<<")
            return
        }

        // CASO A: APROVISIONAMIENTO EXITOSO
        if payload.starts(with: "PROV_OK:") {
            let nuevaClave = String(payload.dropFirst(8))
            UserDefaults.standard.set(nuevaClave, forKey: Self.keyStorageKey)
            self.currentOwnerKey = nuevaClave
            self.isProvisioned = true
            self.isOwnerAuthenticated = true
            self.provisioningError = nil
            addLog(">>> ¡VINCULACIÓN EXITOSA! Clave maestra de dueño registrada de por vida <<<")
            return
        }

        // CASO B: PIN INCORRECTO CON BACKOFF EXPONENCIAL
        if payload.starts(with: "PROV_FAIL:") {
            let partes = payload.split(separator: ":")
            if partes.count >= 3 {
                let intentos = partes[1]
                let espera = partes[2]
                self.pinBlockedSeconds = Int(espera) ?? 5
                self.provisioningError = "PIN incorrecto (#\(intentos)). Penalización de espera: \(espera)s."
                addLog("[ALERTA SEGURIDAD] PIN incorrecto. Bloqueo temporal: \(espera) segundos.")
            }
            return
        }

        // CASO C: BLOQUEO ACTIVO POR FUERZA BRUTA
        if payload.starts(with: "PROV_BLOCKED:") {
            let partes = payload.split(separator: ":")
            let espera = partes.count >= 2 ? partes[1] : "60"
            self.pinBlockedSeconds = Int(espera) ?? 60
            self.provisioningError = "Sistema penalizado por fuerza bruta. Espere \(espera)s."
            addLog("[BLOQUEO] Sistema penalizado por intentos fallidos. Tiempo restante: \(espera)s.")
            return
        }

        // CASO D: DESAFÍO ORDINARIO DE DUEÑO
        if payload.starts(with: "CHALLENGE:") {
            if isProvisioned && !currentOwnerKey.isEmpty {
                let nonce = String(payload.dropFirst(10))
                addLog("Desafío recibido: Nonce \(nonce.prefix(8))...")
                let hmacResponse = computeHMAC(key: currentOwnerKey, message: nonce)
                let responsePayload = "AUTH:\(nonce):\(hmacResponse)"

                if let authChar = authCharacteristic, let respData = responsePayload.data(using: .utf8) {
                    addLog("Firmando con credencial de dueño y respondiendo...")
                    peripheral.writeValue(respData, for: authChar, type: .withResponse)
                }
            } else {
                addLog("Desafío recibido pero el iPhone aún no tiene PIN ingresado.")
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
        if payload.starts(with: "STATUS:") {
            let partes = payload.split(separator: ":")
            if partes.count >= 5 {
                telemetry.relayState = String(partes[1])
                telemetry.zone = String(partes[2])
                telemetry.rssiLora = String(partes[3])
                telemetry.rxCount = String(partes[4])
                if partes.count >= 6 {
                    telemetry.ownerAuth = String(partes[5])
                    if telemetry.ownerAuth == "DUENO_OK" {
                        isOwnerAuthenticated = true
                    }
                }
                if partes.count >= 7, let d = Double(partes[6]) {
                    telemetry.distanceLoraMeters = d
                }
                isReceptorAvailable = true
            }
        }
    }
}
