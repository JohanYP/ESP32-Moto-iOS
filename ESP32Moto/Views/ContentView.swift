import SwiftUI
import LocalAuthentication

public struct ContentView: View {
    @StateObject private var ble = BLEManager.shared
    @State private var showingLogs = false
    @State private var biometricAlertMessage = ""
    @State private var showingBiometricAlert = false

    public var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ESP32 Moto")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Inmovilizador Vehicular • 3FA Dueño")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Circle()
                        .fill(ble.isOwnerAuthenticated ? Color.green : (ble.isConnected ? Color.orange : Color.red))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(ble.isOwnerAuthenticated ? Color.green.opacity(0.4) : Color.clear, lineWidth: 6)
                        )
                }
                .padding(.horizontal)
                .padding(.top, 10)

                // Card de Estado Principal
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: ble.isOwnerAuthenticated ? "person.badge.shield.checkmark.fill" : "person.badge.shield.exclamationmark.fill")
                            .font(.system(size: 36))
                            .foregroundColor(ble.isOwnerAuthenticated ? .green : (ble.isConnected ? .orange : .red))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(ble.isOwnerAuthenticated ? "PROPIETARIO CONFIRMADO" : (ble.isConnected ? "VERIFICANDO DUEÑO..." : "DESCONECTADO"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(ble.isOwnerAuthenticated ? .green : (ble.isConnected ? .orange : .red))
                            Text(ble.isOwnerAuthenticated ? "Llave criptográfica de dueño validada por HMAC-SHA256. Ignición permitida." : "Solo el celular del dueño puede habilitar la motocicleta.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                }
                .padding(.horizontal)

                // Controles Biométricos Face ID (Encendido / Apagado Manual)
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "faceid")
                            .foregroundColor(.cyan)
                        Text("CONTROL DE IGNICIÓN (FACE ID)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            solicitarBiometriaParaAccion(encender: true)
                        }) {
                            HStack {
                                Image(systemName: "power")
                                Text("Encender Moto")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(ble.isOwnerAuthenticated ? Color.green.opacity(0.85) : Color.gray.opacity(0.3))
                            .cornerRadius(14)
                        }
                        .disabled(!ble.isOwnerAuthenticated)

                        Button(action: {
                            solicitarBiometriaParaAccion(encender: false)
                        }) {
                            HStack {
                                Image(systemName: "poweroff")
                                Text("Apagar Moto")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(ble.isOwnerAuthenticated ? Color.red.opacity(0.85) : Color.gray.opacity(0.3))
                            .cornerRadius(14)
                        }
                        .disabled(!ble.isOwnerAuthenticated)
                    }
                }
                .padding(.horizontal)

                // Métricas del Receptor
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        MetricBox(
                            title: "MÓDULO BLE",
                            value: ble.connectedPeripheralName,
                            subtext: ble.isOwnerAuthenticated ? "DUEÑO VINCULADO" : (ble.isReceptorAvailable ? "DETECTADO" : "NO DISPONIBLE"),
                            color: ble.isOwnerAuthenticated ? .green : .orange,
                            icon: "cpu"
                        )
                        MetricBox(
                            title: "RELÉ IGNICIÓN",
                            value: ble.telemetry.relayState,
                            subtext: ble.telemetry.relayState == "ON" ? "MOTOR HABILITADO" : "INMOVILIZADO",
                            color: ble.telemetry.relayState == "ON" ? .green : .red,
                            icon: "bolt.fill"
                        )
                    }

                    HStack(spacing: 12) {
                        MetricBox(
                            title: "POTENCIA BLE",
                            value: ble.isConnected ? "\(ble.receiverRSSI) dBm" : "--",
                            subtext: ble.isConnected ? "En rango seguro" : "Buscando...",
                            color: .cyan,
                            icon: "antenna.radiowaves.left.and.right"
                        )
                        MetricBox(
                            title: "ZONA LLAVERO",
                            value: ble.telemetry.zone,
                            subtext: "LoRa 915 MHz",
                            color: .purple,
                            icon: "key.horizontal.fill"
                        )
                    }
                }
                .padding(.horizontal)

                // Botones Auxiliares
                HStack(spacing: 14) {
                    Button(action: {
                        if ble.isConnected {
                            ble.disconnect()
                        } else {
                            ble.startScan()
                        }
                    }) {
                        HStack {
                            Image(systemName: ble.isConnected ? "bolt.slash.fill" : "arrow.clockwise")
                            Text(ble.isConnected ? "Desconectar" : (ble.isScanning ? "Buscando..." : "Reconectar"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ble.isConnected ? Color.red.opacity(0.6) : Color.blue)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        showingLogs.toggle()
                    }) {
                        HStack {
                            Image(systemName: "terminal.fill")
                            Text("Ver Logs")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                // Terminal de Logs en Vivo
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.cyan)
                        Text("REGISTRO DE SEGURIDAD (BLUETOOTH)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(ble.logs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(log.contains("[ALERTA") ? .red : (log.contains("AUTORIZADO") ? .green : .cyan.opacity(0.9)))
                                        .id(index)
                                }
                            }
                            .padding(10)
                        }
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .onChange(of: ble.logs.count) { _ in
                            if let last = ble.logs.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
        .alert("Seguridad Biométrica", isPresented: $showingBiometricAlert) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(biometricAlertMessage)
        }
        .sheet(isPresented: $showingLogs) {
            FullLogsView(logs: ble.logs)
        }
    }

    private func solicitarBiometriaParaAccion(encender: Bool) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let razon = encender ? "Autentique con Face ID para autorizar el encendido de la motocicleta." : "Autentique con Face ID para apagar el motor de la motocicleta."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: razon) { exito, evalError in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.addLog("Face ID verificado exitosamente. Solicitando encendido...")
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.addLog("Face ID verificado exitosamente. Solicitando apagado...")
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Autenticación biométrica cancelada o fallida."
                        showingBiometricAlert = true
                    }
                }
            }
        } else {
            // Alternativa con código de acceso del dispositivo
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ingrese su código de seguridad para continuar.") { exito, evalError in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Acceso denegado: Código incorrecto."
                        showingBiometricAlert = true
                    }
                }
            }
        }
    }
}

public struct MetricBox: View {
    let title: String
    let value: String
    let subtext: String
    let color: Color
    let icon: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtext)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

public struct FullLogsView: View {
    let logs: [String]
    @Environment(\.dismiss) var dismiss

    public var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(logs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Registro Completo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
