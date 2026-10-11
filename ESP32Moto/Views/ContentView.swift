import SwiftUI
import LocalAuthentication

public struct ContentView: View {
    @StateObject private var ble = BLEManager.shared
    @State private var inputPin = ""
    @State private var showingLogs = false
    @State private var biometricAlertMessage = ""
    @State private var showingBiometricAlert = false
    @State private var showingResetAlert = false

    // Sistema de Diseño: Apple Minimalist Light Palette
    private let bgPrimary = Color(red: 0.96, green: 0.97, blue: 0.98)       // #F5F7FA
    private let cardBg = Color.white                                          // #FFFFFF
    private let borderSubtle = Color.black.opacity(0.06)                     // Suave delineado 1px
    private let textPrimary = Color(red: 0.10, green: 0.12, blue: 0.16)     // #1A1F29
    private let textSecondary = Color(red: 0.45, green: 0.49, blue: 0.55)   // #737D8C
    private let accentBlue = Color(red: 0.00, green: 0.48, blue: 1.00)       // Apple Blue #007AFF
    private let emeraldGreen = Color(red: 0.18, green: 0.72, blue: 0.44)     // #2EB870
    private let rubyRed = Color(red: 0.92, green: 0.26, blue: 0.28)          // #EB4246

    public var body: some View {
        ZStack {
            bgPrimary.ignoresSafeArea()

            if !ble.isProvisioned {
                provisioningView
                    .padding(24)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerBar
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        // Card Principal: Switch Biométrico Face ID
                        heroSwitchCard
                            .padding(.horizontal, 20)

                        // Sección: Distancia Aproximada
                        distanceRadarSection
                            .padding(.horizontal, 20)

                        // Métricas Esenciales
                        telemetryGrid
                            .padding(.horizontal, 20)

                        // Terminal de Registros Desplegable
                        logsSection
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
            Text("Esto eliminará la clave de dueño guardada en este iPhone. Deberá ingresar nuevamente el PIN maestro.")
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

    // MARK: - Componentes Principales

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ESP32 Moto")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)
                Text("Control Vehicular Inalámbrico")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textSecondary)
            }
            Spacer()

            Button(action: {
                showingResetAlert = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(textSecondary)
                    .frame(width: 36, height: 36)
                    .background(cardBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(borderSubtle, lineWidth: 1))
            }

            // Indicador de Estado Discreto
            HStack(spacing: 6) {
                Circle()
                    .fill(ble.isOwnerAuthenticated ? emeraldGreen : (ble.isConnected ? Color.orange : rubyRed))
                    .frame(width: 8, height: 8)
                Text(ble.isOwnerAuthenticated ? "Conectado" : (ble.isConnected ? "Enlazando" : "Desconectado"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(ble.isOwnerAuthenticated ? emeraldGreen : (ble.isConnected ? Color.orange : rubyRed))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(cardBg)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderSubtle, lineWidth: 1)
            )
        }
    }

    private var heroSwitchCard: some View {
        let isIgnitionOn = (ble.telemetry.relayState == "ON")

        return VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IGNICIÓN DEL MOTOR")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textSecondary)
                        .tracking(0.6)

                    Text(isIgnitionOn ? "Encendido" : "Inmovilizado")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(isIgnitionOn ? emeraldGreen : textPrimary)

                    Text(isIgnitionOn ? "Relé activado • Circuito cerrado" : "Relé apagado • Chispa cortada")
                        .font(.system(size: 13))
                        .foregroundColor(textSecondary)
                }

                Spacer()

                // Switch Nativo Estilizado
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isIgnitionOn ? emeraldGreen : Color.black.opacity(0.12))
                        .frame(width: 64, height: 36)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                        .offset(x: isIgnitionOn ? 14 : -14)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isIgnitionOn)
                }
                .onTapGesture {
                    if ble.isOwnerAuthenticated {
                        solicitarFaceIDParaConmutar(encender: !isIgnitionOn)
                    } else {
                        biometricAlertMessage = "Debe esperar a que la motocicleta autentique su celular vía Bluetooth."
                        showingBiometricAlert = true
                    }
                }
            }

            Divider()
                .background(borderSubtle)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "faceid")
                        .font(.system(size: 14))
                        .foregroundColor(accentBlue)
                    Text("Protegido con Face ID")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(textSecondary)
                }
                Spacer()
                Text("Toque el switch para cambiar")
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary.opacity(0.8))
            }
        }
        .padding(20)
        .background(cardBg)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
    }

    private var distanceRadarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISTANCIA APROXIMADA")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(0.6)

            HStack(spacing: 12) {
                // Card 1: Distancia Celular <-> Moto
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundColor(accentBlue)
                        Text("Celular • Moto")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textPrimary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(ble.isConnected ? String(format: "%.1f", ble.telemetry.distanceBleMeters) : "--")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(textPrimary)
                        Text("m")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(textSecondary)
                    }

                    Text(ble.isConnected ? "\(ble.receiverRSSI) dBm (Bluetooth)" : "Desconectado")
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderSubtle, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)

                // Card 2: Distancia Llavero <-> Moto
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(emeraldGreen)
                        Text("Llavero • Moto")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textPrimary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        let d = ble.telemetry.distanceLoraMeters
                        Text(d > 0 ? String(format: "%.2f", d) : "--")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(textPrimary)
                        Text("m")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(textSecondary)
                    }

                    Text("\(ble.telemetry.rssiLora) dBm (LoRa 915M)")
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderSubtle, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
            }
        }
    }

    private var telemetryGrid: some View {
        HStack(spacing: 12) {
            // Módulo Receptor
            VStack(alignment: .leading, spacing: 6) {
                Text("RECEPTOR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textSecondary)
                Text(ble.connectedPeripheralName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)
                Text(ble.isReceptorAvailable ? "En rango seguro" : "Buscando...")
                    .font(.system(size: 11))
                    .foregroundColor(ble.isReceptorAvailable ? emeraldGreen : textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBg)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderSubtle, lineWidth: 1))

            // Rango LoRa
            VStack(alignment: .leading, spacing: 6) {
                Text("RANGO LLAVERO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textSecondary)
                Text(ble.telemetry.zone)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(ble.telemetry.zone.contains("AUTORIZADO") ? emeraldGreen : textPrimary)
                Text("\(ble.telemetry.rxCount) paquetes validados")
                    .font(.system(size: 11))
                    .foregroundColor(textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBg)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderSubtle, lineWidth: 1))
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REGISTRO DE ACTIVIDAD")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textSecondary)
                    .tracking(0.6)
                Spacer()
                Button(action: {
                    showingLogs.toggle()
                }) {
                    Text("Ver completo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentBlue)
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
                .frame(height: 120)
                .background(cardBg)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderSubtle, lineWidth: 1))
                .onChange(of: ble.logs.count) { _ in
                    if let last = ble.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Pantalla de Aprovisionamiento (Modo Claro)

    private var provisioningView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 50))
                    .foregroundColor(accentBlue)

                Text("Vincular Motocicleta")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Ingrese el PIN de fábrica para autorizar este iPhone como el único teléfono propietario.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(textSecondary)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 16) {
                SecureField("PIN de 6 dígitos (ej. 123456)", text: $inputPin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(textPrimary)
                    .padding()
                    .background(bgPrimary)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderSubtle, lineWidth: 1))

                if let err = ble.provisioningError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(rubyRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: {
                    ble.provisionWithPin(inputPin.trimmingCharacters(in: .whitespacesAndNewlines))
                }) {
                    Text("Vincular como Propietario")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(inputPin.count >= 4 ? accentBlue : Color.gray.opacity(0.4))
                        .cornerRadius(14)
                }
                .disabled(inputPin.count < 4)
            }
            .padding(22)
            .background(cardBg)
            .cornerRadius(22)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(borderSubtle, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)

            Spacer()
        }
    }

    // MARK: - Face ID y Lógica

    private func solicitarFaceIDParaConmutar(encender: Bool) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let motivo = encender ? "Autentique con Face ID para autorizar el encendido de la motocicleta." : "Autentique con Face ID para apagar el motor de la motocicleta."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: motivo) { exito, _ in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.addLog("Face ID verificado exitosamente. Encendiendo moto...")
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.addLog("Face ID verificado exitosamente. Inmovilizando moto...")
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Autenticación Face ID cancelada o no reconocida."
                        showingBiometricAlert = true
                    }
                }
            }
        } else {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ingrese su código maestro para autorizar.") { exito, _ in
                DispatchQueue.main.async {
                    if exito {
                        if encender {
                            ble.sendCommand("IGNITION_ON")
                        } else {
                            ble.sendCommand("IGNITION_OFF")
                        }
                    } else {
                        biometricAlertMessage = "Código incorrecto."
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
                        ble.addLog("Face ID verificado. Restableciendo PIN maestro a 123456...")
                        ble.sendCommand("CONFIRM_RESET")
                        ble.isResetRequested = false
                    } else {
                        biometricAlertMessage = "Autenticación cancelada. Reinicio bloqueado."
                        showingBiometricAlert = true
                    }
                }
            }
        }
    }

    private func colorParaLog(_ log: String) -> Color {
        if log.contains("[ALERTA") || log.contains("FAIL") || log.contains("DENEGADO") {
            return rubyRed
        } else if log.contains("AUTORIZADO") || log.contains("OK") || log.contains("PROPIETARIO") {
            return emeraldGreen
        } else if log.contains("Face ID") || log.contains("Desafío") {
            return accentBlue
        } else {
            return textSecondary
        }
    }
}

public struct HardwareResetConfirmationSheet: View {
    let onConfirmFaceID: () -> Void
    let onCancel: () -> Void

    public var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.98).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 54))
                        .foregroundColor(Color(red: 0.92, green: 0.26, blue: 0.28))

                    Text("Solicitud de Reinicio de PIN")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.10, green: 0.12, blue: 0.16))

                    Text("Se ha presionado el botón físico en el llavero o la motocicleta para restablecer el PIN maestro de seguridad a 123456.\n\nPara confirmar que usted es el propietario legítimo y evitar reinicios no autorizados por robo, autentique con Face ID.")
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.55))
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 12) {
                    Button(action: onConfirmFaceID) {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .bold))
                            Text("Autorizar Reinicio con Face ID")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(red: 0.92, green: 0.26, blue: 0.28))
                        .cornerRadius(14)
                    }

                    Button(action: onCancel) {
                        Text("Rechazar / Cancelar Solicitud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(20)
        }
    }
}

public struct FullLogsView: View {
    let logs: [String]
    @Environment(\.dismiss) var dismiss

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.98).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(logs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(red: 0.10, green: 0.12, blue: 0.16))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Registro de Actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
