import SwiftUI
import LocalAuthentication

public struct ContentView: View {
    @StateObject private var ble = BLEManager.shared
    @State private var inputPin = ""
    @State private var showingLogs = false
    @State private var biometricAlertMessage = ""
    @State private var showingBiometricAlert = false
    @State private var showingResetAlert = false

    private let bgCanvas = Color(red: 0.05, green: 0.06, blue: 0.08)
    private let cardSurface = Color(red: 0.09, green: 0.11, blue: 0.15)
    private let borderCard = Color.white.opacity(0.08)
    private let emeraldGreen = Color(red: 0.06, green: 0.84, blue: 0.55)
    private let roseRed = Color(red: 0.98, green: 0.28, blue: 0.42)
    private let electricCyan = Color(red: 0.18, green: 0.80, blue: 0.98)
    private let vibrantPurple = Color(red: 0.68, green: 0.42, blue: 0.98)

    public var body: some View {
        ZStack {
            bgCanvas.ignoresSafeArea()

            if !ble.isProvisioned {
                // Vista de Aprovisionamiento Inicial / PIN
                provisioningView
                    .padding(24)
            } else {
                // Dashboard Automotriz Principal
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerBar
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        biometricSwitchCard
                            .padding(.horizontal, 20)

                        distanceRadarSection
                            .padding(.horizontal, 20)

                        telemetryGrid
                            .padding(.horizontal, 20)

                        logsConsoleSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .alert("Seguridad Biométrica", isPresented: $showingBiometricAlert) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(biometricAlertMessage)
        }
        .alert("Restablecer Vinculación Local", isPresented: $showingResetAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Restablecer", role: .destructive) {
                ble.resetLocalProvisioning()
            }
        } message: {
            Text("Esto eliminará la clave de dueño guardada en este iPhone. Tendrá que volver a ingresar el PIN maestro de 6 dígitos.")
        }
        .sheet(isPresented: $showingLogs) {
            FullLogsView(logs: ble.logs)
        }
        .sheet(isPresented: $ble.isResetRequested) {
            HardwareResetConfirmationSheet(
                onConfirmFaceID: {
                    solicitarFaceIDParaReset()
                },
                onCancel: {
                    ble.sendCommand("CANCEL_RESET")
                    ble.isResetRequested = false
                }
            )
        }
    }

    // MARK: - Pantalla de Aprovisionamiento con PIN

    private var provisioningView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(electricCyan)

                Text("Vincular Motocicleta")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("Ingrese el PIN de fábrica para autorizar este iPhone como el único teléfono propietario.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 16) {
                // Campo de PIN
                SecureField("PIN de 6 dígitos (ej. 123456)", text: $inputPin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderCard, lineWidth: 1)
                    )

                if let err = ble.provisioningError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(roseRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: {
                    ble.provisionWithPin(inputPin.trimmingCharacters(in: .whitespacesAndNewlines))
                }) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Vincular como Propietario")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(inputPin.count >= 4 ? electricCyan : Color.gray.opacity(0.3))
                    .cornerRadius(16)
                }
                .disabled(inputPin.count < 4)
            }
            .padding(20)
            .background(cardSurface)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(borderCard, lineWidth: 1)
            )

            HStack(spacing: 6) {
                Circle()
                    .fill(ble.isConnected ? emeraldGreen : roseRed)
                    .frame(width: 8, height: 8)
                Text(ble.isConnected ? "Conectado por BLE con la moto" : "Buscando módulo ESP32 Moto...")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }

    // MARK: - Componentes del Dashboard

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("ESP32 Moto")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("3FA")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(emeraldGreen)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(emeraldGreen.opacity(0.15))
                        .cornerRadius(6)
                }
                Text("Inmovilizador Vehicular • Popayán")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }
            Spacer()

            Button(action: {
                showingResetAlert = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(ble.isOwnerAuthenticated ? emeraldGreen : (ble.isConnected ? Color.orange : roseRed))
                    .frame(width: 10, height: 10)
                Text(ble.isOwnerAuthenticated ? "DUEÑO" : (ble.isConnected ? "ENLAZANDO" : "OFFLINE"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ble.isOwnerAuthenticated ? emeraldGreen : (ble.isConnected ? Color.orange : roseRed))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
    }

    private var biometricSwitchCard: some View {
        let isIgnitionOn = (ble.telemetry.relayState == "ON")
        
        return VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                            .foregroundColor(electricCyan)
                            .font(.system(size: 16, weight: .bold))
                        Text("CONTROL DE IGNICIÓN BIOMÉTRICO")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(0.8)
                    }

                    Text(isIgnitionOn ? "MOTOR HABILITADO" : "MOTOR INMOVILIZADO")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(isIgnitionOn ? emeraldGreen : roseRed)

                    Text(isIgnitionOn ? "Relé cerrado (ignición activa)." : "Relé abierto (chispa cortada).")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isIgnitionOn ? emeraldGreen.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 72, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(isIgnitionOn ? emeraldGreen : Color.white.opacity(0.15), lineWidth: 2)
                        )

                    Circle()
                        .fill(isIgnitionOn ? emeraldGreen : Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .shadow(color: isIgnitionOn ? emeraldGreen.opacity(0.6) : Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
                        .offset(x: isIgnitionOn ? 15 : -15)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isIgnitionOn)
                }
                .onTapGesture {
                    if ble.isOwnerAuthenticated {
                        solicitarFaceIDParaConmutar(encender: !isIgnitionOn)
                    } else {
                        biometricAlertMessage = "Debe esperar a que la app verifique su identidad de propietario con la moto."
                        showingBiometricAlert = true
                    }
                }
            }

            HStack {
                HStack(spacing: 5) {
                    Image(systemName: ble.isOwnerAuthenticated ? "checkmark.shield.fill" : "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(ble.isOwnerAuthenticated ? emeraldGreen : .orange)
                    Text(ble.isOwnerAuthenticated ? "Autenticación de Propietario Aprobada" : "Verificando Credencial Criptográfica...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ble.isOwnerAuthenticated ? emeraldGreen : .orange)
                }
                Spacer()
                Text("Toque el switch para cambiar")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.8))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(borderCard, lineWidth: 1)
                )
        )
    }

    private var distanceRadarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.north.line.fill")
                    .foregroundColor(electricCyan)
                Text("DISTANCIA APROXIMADA EN TIEMPO REAL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(0.6)
                Spacer()
            }

            HStack(spacing: 12) {
                // Tarjeta 1: Celular • Moto (BLE)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(electricCyan)
                        Text("CELULAR • MOTO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(ble.isConnected ? String(format: "%.1f", ble.telemetry.distanceBleMeters) : "--")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("metros")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(electricCyan)
                                .frame(width: max(0, min(geo.size.width * CGFloat(1.0 - (ble.telemetry.distanceBleMeters / 15.0)), geo.size.width)), height: 5)
                        }
                    }
                    .frame(height: 5)

                    Text(ble.isConnected ? "\(ble.receiverRSSI) dBm (Bluetooth LE)" : "Fuera de alcance")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ble.isConnected ? electricCyan : .gray)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(borderCard, lineWidth: 1)
                        )
                )

                // Tarjeta 2: Llavero • Moto (LoRa 915 MHz)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(vibrantPurple)
                        Text("LLAVERO • MOTO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        let dLora = ble.telemetry.distanceLoraMeters
                        Text(dLora > 0 ? String(format: "%.2f", dLora) : "--")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("metros")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(vibrantPurple)
                                .frame(width: max(0, min(geo.size.width * CGFloat(1.0 - (ble.telemetry.distanceLoraMeters / 6.0)), geo.size.width)), height: 5)
                        }
                    }
                    .frame(height: 5)

                    Text("\(ble.telemetry.rssiLora) dBm (\(ble.telemetry.zone))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(vibrantPurple)
                        .lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(borderCard, lineWidth: 1)
                        )
                )
            }
        }
    }

    private var telemetryGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricItemCard(
                    title: "HARDWARE MOTO",
                    value: ble.connectedPeripheralName,
                    subtext: ble.isOwnerAuthenticated ? "ENLAZADO Y SEGURO" : "BUSCANDO RECEPTOR",
                    tint: ble.isOwnerAuthenticated ? emeraldGreen : .orange,
                    systemIcon: "cpu"
                )

                MetricItemCard(
                    title: "RADIO SUB-GHZ",
                    value: "915.0 MHz",
                    subtext: "LoRa SF7 / Semtech SX1262",
                    tint: vibrantPurple,
                    systemIcon: "antenna.radiowaves.left.and.right"
                )
            }

            HStack(spacing: 12) {
                MetricItemCard(
                    title: "PAQUETES 3FA",
                    value: "\(ble.telemetry.rxCount) RX",
                    subtext: "HMAC-SHA256 Nonce",
                    tint: electricCyan,
                    systemIcon: "shield.lefthalf.filled"
                )

                MetricItemCard(
                    title: "ESTADO DE LLAVE",
                    value: ble.telemetry.zone,
                    subtext: ble.telemetry.zone.contains("AUTORIZADO") ? "Rango Seguro (<0.5m)" : "Distancia Lejana",
                    tint: ble.telemetry.zone.contains("AUTORIZADO") ? emeraldGreen : roseRed,
                    systemIcon: "lock.rotation"
                )
            }
        }
    }

    private var logsConsoleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(electricCyan)
                Text("REGISTRO DE AUDITORÍA Y TELEMETRÍA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(0.6)
                Spacer()

                Button(action: {
                    showingLogs.toggle()
                }) {
                    Text("Pantalla Completa")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(electricCyan)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(ble.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(colorParaLog(log))
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 140)
                .background(Color.black.opacity(0.45))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderCard, lineWidth: 1)
                )
                .onChange(of: ble.logs.count) { _ in
                    if let last = ble.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Face ID

    private func solicitarFaceIDParaConmutar(encender: Bool) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let motivo = encender ? "Autentique con Face ID para autorizar el encendido de la motocicleta." : "Autentique con Face ID para apagar el motor de la motocicleta."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: motivo) { exito, evalError in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.addLog("Face ID verificado con éxito. Ordenando encendido...")
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.addLog("Face ID verificado con éxito. Ordenando apagado...")
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Autenticación Face ID cancelada o no reconocida."
                        showingBiometricAlert = true
                    }
                }
            }
        } else {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ingrese su código maestro para autorizar.") { exito, evalError in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Código de seguridad incorrecto."
                        showingBiometricAlert = true
                    }
                }
            }
        }
    }

    private func solicitarFaceIDParaReset() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Confirme con Face ID para autorizar el restablecimiento del PIN maestro de su motocicleta.") { exito, _ in
                DispatchQueue.main.async {
                    if exito {
                        ble.addLog("Face ID verificado exitosamente para restablecimiento de PIN.")
                        ble.sendCommand("CONFIRM_RESET")
                        ble.isResetRequested = false
                    } else {
                        biometricAlertMessage = "Autenticación Face ID cancelada o fallida. El reinicio de PIN fue bloqueado."
                        showingBiometricAlert = true
                    }
                }
            }
        } else {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ingrese su código maestro para autorizar el reinicio.") { exito, _ in
                DispatchQueue.main.async {
                    if exito {
                        ble.sendCommand("CONFIRM_RESET")
                        ble.isResetRequested = false
                    } else {
                        biometricAlertMessage = "Código incorrecto. Reinicio bloqueado."
                        showingBiometricAlert = true
                    }
                }
            }
        }
    }

    private func colorParaLog(_ log: String) -> Color {
        if log.contains("[ALERTA") || log.contains("FAIL") || log.contains("DENEGADO") {
            return roseRed
        } else if log.contains("AUTORIZADO") || log.contains("OK") || log.contains("PROPIETARIO") {
            return emeraldGreen
        } else if log.contains("Face ID") || log.contains("Desafío") {
            return electricCyan
        } else {
            return Color.white.opacity(0.85)
        }
    }
}

public struct MetricItemCard: View {
    let title: String
    let value: String
    let subtext: String
    let tint: Color
    let systemIcon: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: systemIcon)
                    .font(.system(size: 13))
                    .foregroundColor(tint)
            }

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtext)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(tint)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
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

public struct HardwareResetConfirmationSheet: View {
    let onConfirmFaceID: () -> Void
    let onCancel: () -> Void

    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.98, green: 0.28, blue: 0.42))

                    Text("Solicitud de Reinicio de PIN")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Se ha presionado el botón físico en el llavero o la motocicleta para restablecer el PIN maestro de seguridad a 123456.\n\nPara confirmar que usted es el propietario legítimo y evitar reinicios no autorizados por robo, autentique con Face ID.")
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 12) {
                    Button(action: onConfirmFaceID) {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                                .font(.system(size: 18, weight: .bold))
                            Text("Autorizar Reinicio con Face ID")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.98, green: 0.28, blue: 0.42))
                        .cornerRadius(16)
                    }

                    Button(action: onCancel) {
                        Text("Rechazar / Cancelar Solicitud")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(20)
        }
    }
}
